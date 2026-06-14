#include "tellercore/ffi.h"

#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>

#include <nlohmann/json.hpp>

#include "tellercore/db.hpp"
#include "tellercore/error.hpp"
#include "tellercore/json_io.hpp"
#include "tellercore/mailcart.hpp"
#include "tellercore/persist.hpp"
#include "tellercore/profile.hpp"

namespace {

using namespace tellercore;
using nlohmann::json;

struct CoreState {
    std::unique_ptr<db::Db> db;
    std::unique_ptr<mailcart::Client> mailcart_client;
    bool mailcart_enabled = false;
};

std::mutex g_mutex;
// Intentionally leaked, never freed by a static destructor: closing SQLCipher
// during process teardown can crash after the library's own static cleanup has
// run. teller_core_close() exists for callers wanting an orderly shutdown.
CoreState* g_core = nullptr;

// #R001: Traceability for function `dup_string`.
char* dup_string(const std::string& value) {
    char* out = static_cast<char*>(std::malloc(value.size() + 1));
    if (out != nullptr) std::memcpy(out, value.c_str(), value.size() + 1);
    return out;
}

// #R001: Traceability for function `dump_replacing_invalid_utf8`.
std::string dump_replacing_invalid_utf8(const json& value) {
    return value.dump(-1, ' ', false, json::error_handler_t::replace);
}

// #R001: Traceability for function `ok_envelope`.
char* ok_envelope(const json& body) {
    return dup_string(dump_replacing_invalid_utf8(json{{"ok", true}, {"body", body}}));
}

// #R001: Traceability for function `ok_bare`.
char* ok_bare() { return dup_string(dump_replacing_invalid_utf8(json{{"ok", true}})); }

// #R001: Traceability for function `error_envelope`.
char* error_envelope(int status, const std::string& detail) {
    return dup_string(
        dump_replacing_invalid_utf8(json{{"ok", false}, {"status", status}, {"detail", detail}}));
}

// #R001: Traceability for function `read_file`.
std::string read_file(const std::string& path) {
    std::ifstream in(path);
    if (!in.is_open()) throw ApiError(500, "cannot open DDL file: " + path);
    std::stringstream buffer;
    buffer << in.rdbuf();
    return buffer.str();
}

// #R001: Traceability for function `profile_from_config`.
DbProfile profile_from_config(const json& config) {
    const std::string sqlite_path = config.value("sqlite_path", "");
    if (!sqlite_path.empty()) {
        DbProfile p;
        p.name = "sqlite";
        p.target = DbTarget::kSqlite;
        p.sqlite_path = sqlite_path;
        p.sqlcipher_key = config.value("sqlcipher_key", "");
        return p;
    }
    return resolve_profile();
}

// #R001: Traceability for function `invoke_op`.
json invoke_op(CoreState& core, const std::string& op, const json& args) {
    if (op == "persist") {
        const json identities = args.contains("identities") ? args["identities"] : json::array();
        const json txns = args.contains("transactions_by_account") ? args["transactions_by_account"]
                                                                    : json::object();
        const json balances = args.contains("balances_by_account") ? args["balances_by_account"]
                                                                    : json::object();
        persist::persist_all(*core.db, identities, txns, balances);
        return json{{"identity_records", identities.size()},
                    {"accounts_with_transactions", txns.is_object() ? txns.size() : 0},
                    {"accounts_with_balances", balances.is_object() ? balances.size() : 0}};
    }
    if (op == "resolve_profile") {
        const DbProfile p = resolve_profile();
        const char* target = p.target == DbTarget::kSqlite   ? "sqlite"
                             : p.target == DbTarget::kManaged ? "managed"
                                                              : "local";
        json body{{"name", p.name}, {"target", target}};
        if (p.target == DbTarget::kSqlite) {
            body["sqlite_path"] = p.sqlite_path;
            body["has_sqlcipher_key"] = !p.sqlcipher_key.empty();
        } else {
            body["host"] = p.host;
            body["port"] = p.port;
            body["dbname"] = p.dbname;
            body["user"] = p.user;
            body["search_path"] = p.search_path;
            body["runtime_role"] = p.runtime_role;
            body["sslmode"] = p.sslmode;
        }
        return body;
    }
    if (op == "fetch_message") {
        if (core.mailcart_client == nullptr) {
            throw ApiError(503, "mailcart client unavailable (offline or disabled)");
        }
        const std::string id = args.value("email_message_id", "");
        try {
            return core.mailcart_client->get_message(id);
        } catch (const mailcart::MailcartError& exc) {
            throw ApiError(exc.status_code, exc.message);
        }
    }
    if (op == "search_messages") {
        if (core.mailcart_client == nullptr) {
            throw ApiError(503, "mailcart client unavailable (offline or disabled)");
        }
        const std::string query = args.value("query", "");
        const int limit = args.value("limit", 20);
        try {
            return core.mailcart_client->search(query, limit);
        } catch (const mailcart::MailcartError& exc) {
            throw ApiError(exc.status_code, exc.message);
        }
    }
    throw ApiError(404, "unknown op: " + op);
}

} // namespace

extern "C" {

// #R001: Traceability for function `teller_core_open`.
char* teller_core_open(const char* config_json) {
    std::lock_guard<std::mutex> lock(g_mutex);
    try {
        json config = json::object();
        if (config_json != nullptr && config_json[0] != '\0') {
            config = json::parse(config_json, nullptr, false);
            if (config.is_discarded()) return error_envelope(400, "open config was not valid JSON");
        }
        const DbProfile profile = profile_from_config(config);
        const std::string bootstrap = config.value("bootstrap_ddl_path", "");
        if (!bootstrap.empty() && profile.target == DbTarget::kSqlite) {
            db::SqliteDb::bootstrap_file(profile.sqlite_path, profile.sqlcipher_key,
                                         read_file(bootstrap));
        }
        auto state = std::make_unique<CoreState>();
        state->db = db::open_from_profile(profile);
        state->mailcart_enabled = config.value("enable_mailcart", false);
        if (state->mailcart_enabled) {
            try {
                state->mailcart_client = mailcart::make_default_client();
            } catch (const mailcart::MailcartError&) {
                state->mailcart_client = nullptr; // offline-tolerant
            }
        }
        delete g_core;
        g_core = state.release();
        return ok_bare();
    } catch (const ApiError& exc) {
        return error_envelope(exc.status(), exc.detail());
    } catch (const std::exception& exc) {
        return error_envelope(500, exc.what());
    }
}

// #R001: Traceability for function `teller_core_invoke`.
char* teller_core_invoke(const char* request_json) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_core == nullptr) return error_envelope(409, "core is not open; call teller_core_open first");
    try {
        if (request_json == nullptr) return error_envelope(400, "request was null");
        json request = json::parse(request_json, nullptr, false);
        if (request.is_discarded()) return error_envelope(400, "request was not valid JSON");
        const std::string op = request.value("op", "");
        if (op.empty()) return error_envelope(400, "request is missing 'op'");
        const json args = request.contains("args") && request["args"].is_object()
                              ? request["args"]
                              : json::object();
        return ok_envelope(invoke_op(*g_core, op, args));
    } catch (const ApiError& exc) {
        return error_envelope(exc.status(), exc.detail());
    } catch (const std::exception& exc) {
        return error_envelope(500, exc.what());
    }
}

// #R001: Traceability for function `teller_core_free`.
void teller_core_free(char* ptr) { std::free(ptr); }

// #R001: Traceability for function `teller_core_close`.
char* teller_core_close(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    delete g_core;
    g_core = nullptr;
    return ok_bare();
}

} // extern "C"
