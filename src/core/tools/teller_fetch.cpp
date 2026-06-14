// teller_fetch: C++ port of 07_fetch_teller_api_data.py.
//
// mTLS client to https://api.teller.io that fetches identities, transactions
// (paginated) and balances for each enrollment context found under ~/.teller,
// then persists them through tellercore::persist (the same upsert/reconcile
// logic the Python teller_persist used). The retired Python script remains the
// ingest reference oracle.
//
//   teller_fetch [--dry-run] [--institution_id <id>] [--token <token>]
//
// Auth/TLS material (mirrors the Python client):
//   ~/.teller/auth_token.json        {"current": "<token>"}  (default context)
//   ~/.teller/auth_token_<suffix>.json                       (extra contexts)
//   ~/.teller/certificate.pem , ~/.teller/private_key.pem    (client mTLS)
// NOLINTBEGIN(concurrency-mt-unsafe,bugprone-empty-catch,bugprone-exception-escape)

#include <httplib.h>

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "tellercore/db.hpp"
#include "tellercore/error.hpp"
#include "tellercore/persist.hpp"
#include "tellercore/profile.hpp"

using namespace tellercore;
using nlohmann::json;
namespace fs = std::filesystem;

namespace {

constexpr const char* kApiHost = "api.teller.io";
constexpr int kApiPort = 443;
constexpr int kTimeoutSeconds = 30;

// #R001: Traceability for function `teller_dir`.
fs::path teller_dir() {
    const char* home = std::getenv("HOME");
    return fs::path(home ? home : "/") / ".teller";
}

// #R001: Traceability for function `read_text`.
std::string read_text(const fs::path& path) {
    std::ifstream in(path);
    if (!in.is_open()) return "";
    std::stringstream buffer;
    buffer << in.rdbuf();
    std::string s = buffer.str();
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' ')) s.pop_back();
    return s;
}

// #R001: Traceability for function `read_token_file`.
std::string read_token_file(const fs::path& path) {
    const std::string body = read_text(path);
    if (body.empty()) return "";
    json parsed = json::parse(body, nullptr, false);
    if (parsed.is_discarded() || !parsed.is_object()) return "";
    return parsed.value("current", "");
}

struct Context {
    std::string token;
    std::string institution_id;
    std::string source;
};

// Default + suffix-token enrollment contexts, deduped by token (a subset of the
// Python discovery: metadata/enrollment inference are deferred).
// #R001: Traceability for function `build_contexts`.
std::vector<Context> build_contexts(const std::string& token_override) {
    std::vector<Context> contexts;
    std::vector<std::string> seen_tokens;
    auto add = [&](const std::string& token, const std::string& inst, const std::string& source) {
        if (token.empty()) return;
        for (const auto& t : seen_tokens) {
            if (t == token) return;
        }
        seen_tokens.push_back(token);
        contexts.push_back({token, inst, source});
    };
    if (!token_override.empty()) {
        add(token_override, "", "override");
        return contexts;
    }
    add(read_token_file(teller_dir() / "auth_token.json"), "", "default");
    std::error_code ec;
    if (fs::is_directory(teller_dir(), ec)) {
        std::vector<fs::path> token_files;
        for (const auto& entry : fs::directory_iterator(teller_dir(), ec)) {
            const std::string name = entry.path().filename().string();
            if (name.rfind("auth_token_", 0) == 0 && entry.path().extension() == ".json") {
                token_files.push_back(entry.path());
            }
        }
        std::sort(token_files.begin(), token_files.end());
        for (const auto& path : token_files) {
            std::string suffix = path.stem().string().substr(std::string("auth_token_").size());
            add(read_token_file(path), suffix, "suffix");
        }
    }
    return contexts;
}

// #R001: Traceability for function `path_from_url`.
std::string path_from_url(const std::string& url) {
    const std::string scheme = "https://";
    if (url.rfind(scheme, 0) != 0) return url;
    const auto slash = url.find('/', scheme.size());
    return slash == std::string::npos ? "/" : url.substr(slash);
}

class TellerApiClient {
public:
    // #R001: Traceability for function `TellerApiClient`.
    explicit TellerApiClient(const std::string& token) {
        const std::string cert = (teller_dir() / "certificate.pem").string();
        const std::string key = (teller_dir() / "private_key.pem").string();
        client_ = std::make_unique<httplib::SSLClient>(kApiHost, kApiPort, cert, key);
        client_->set_basic_auth(token, "");
        client_->set_default_headers({{"Accept", "application/json"},
                                      {"Content-Type", "application/json"}});
        client_->set_connection_timeout(kTimeoutSeconds, 0);
        client_->set_read_timeout(kTimeoutSeconds, 0);
    }

    // #R001: Traceability for function `get`.
    json get(const std::string& path_or_url) {
        const std::string path = path_from_url(path_or_url);
        auto result = client_->Get(path);
        if (!result) {
            throw ApiError(502, "Teller API request failed: " + httplib::to_string(result.error()));
        }
        json parsed = json::parse(result->body, nullptr, false);
        if (result->status != 200) {
            std::string code, message = result->body;
            if (!parsed.is_discarded() && parsed.is_object() && parsed.contains("error")) {
                code = parsed["error"].value("code", "");
                message = parsed["error"].value("message", result->body);
            }
            throw ApiError(result->status,
                           "Teller API " + std::to_string(result->status) +
                               (code.empty() ? "" : " [" + code + "]") + ": " + message);
        }
        if (parsed.is_discarded()) throw ApiError(502, "Teller API returned invalid JSON for " + path);
        return parsed;
    }

private:
    std::unique_ptr<httplib::SSLClient> client_;
};

// Pages /accounts/{id}/transactions via the from_id cursor (port of
// _fetch_all_transactions), guarding against runaway/repeated cursors.
// #R001: Traceability for function `fetch_all_transactions`.
json fetch_all_transactions(TellerApiClient& client, const std::string& txn_url) {
    json all = json::array();
    std::vector<std::string> seen_cursors;
    int max_pages = 1000;
    if (const char* env = std::getenv("TELLER_TXN_MAX_PAGES")) {
        try {
            const int parsed = std::stoi(env);
            if (parsed > 0) max_pages = parsed;
        } catch (...) {
        }
    }
    std::string url = txn_url;
    bool first = true;
    for (int page_count = 0;; ++page_count) {
        if (page_count >= max_pages) {
            throw ApiError(0, "Transaction pagination exceeded maximum pages (" +
                                  std::to_string(max_pages) + ")");
        }
        const std::string request_url = first ? url : url + "?from_id=" + seen_cursors.back();
        first = false;
        json page = client.get(request_url);
        if (!page.is_array() || page.empty()) break;
        for (const auto& txn : page) all.push_back(txn);
        const std::string last_id = page.back().value("id", "");
        for (const auto& cursor : seen_cursors) {
            if (cursor == last_id) {
                throw ApiError(0, "Transaction pagination repeated cursor from_id=" + last_id);
            }
        }
        seen_cursors.push_back(last_id);
    }
    return all;
}

} // namespace

// #R001: Traceability for function `main`.
int main(int argc, char** argv) {
    bool dry_run = false;
    std::string institution_filter;
    std::string token_override;
    std::string dump_payload_path;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--dry-run") dry_run = true;
        else if (arg == "--institution_id" && i + 1 < argc) institution_filter = argv[++i];
        else if (arg == "--token" && i + 1 < argc) token_override = argv[++i];
        else if (arg == "--dump-payload" && i + 1 < argc) dump_payload_path = argv[++i];
        else {
            std::cerr << "usage: teller_fetch [--dry-run] [--institution_id <id>] [--token <token>]"
                         " [--dump-payload <path>]\n";
            return 2;
        }
    }

    try {
        const std::vector<Context> contexts = build_contexts(token_override);
        if (contexts.empty()) {
            throw ApiError(0, "No auth token found. Save a connection token via the classy macOS "
                              "Connect tab (writes ~/.teller/auth_token.json).");
        }

        json raw_identities = json::array();
        json txns_by_account = json::object();
        json balances_by_account = json::object();

        struct FetchFailure {
            std::string scope;  // institution / account label for the report
            int status = 0;
            std::string detail;
        };
        std::vector<FetchFailure> failures;
        bool saw_disconnected = false;
        auto note_failure = [&](const std::string& scope, int status, const std::string& detail) {
            failures.push_back({scope, status, detail});
            if (detail.find("enrollment.disconnected") != std::string::npos) saw_disconnected = true;
        };

        for (const auto& context : contexts) {
            // Context-level failures (token/identity) discard only this enrollment;
            // healthy enrollments still ingest. 07_fetch is resilient across
            // contexts; this port additionally isolates failures per account so a
            // single inactive enrollment cannot sink its healthy siblings.
            json identities;
            try {
                TellerApiClient identity_client(context.token);
                identities = identity_client.get("/identity");
            } catch (const ApiError& exc) {
                const std::string scope =
                    context.institution_id.empty() ? "enrollment(" + context.source + ")"
                                                    : "institution=" + context.institution_id;
                note_failure(scope, exc.status(), exc.detail());
                continue;
            }

            TellerApiClient client(context.token);
            for (const auto& item : identities) {
                const json& account = item.at("account");
                const std::string inst_id = account.at("institution").value("id", "");
                if (!institution_filter.empty() && inst_id != institution_filter) continue;
                const std::string account_id = account.value("id", "");
                const std::string inst_name = account.at("institution").value("name", "");
                std::cout << "Account fetched: id=" << account_id << " institution=" << inst_name
                          << "\n";
                // Per-account all-or-nothing: a partial fetch is never persisted,
                // so the stale-pending reconciliation never deletes against an
                // incomplete transaction set.
                try {
                    json account_txns;
                    bool has_txns = false;
                    const std::string txn_url = account.at("links").value("transactions", "");
                    if (!txn_url.empty()) {
                        account_txns = fetch_all_transactions(client, txn_url);
                        std::cout << "  Transactions fetched: " << account_txns.size() << "\n";
                        has_txns = true;
                    }
                    json account_bal;
                    bool has_bal = false;
                    const std::string bal_url = account.at("links").value("balances", "");
                    if (!bal_url.empty()) {
                        account_bal = client.get(bal_url);
                        std::cout << "  Balances fetched.\n";
                        has_bal = true;
                    }
                    raw_identities.push_back(item);
                    if (has_txns) txns_by_account[account_id] = std::move(account_txns);
                    if (has_bal) balances_by_account[account_id] = std::move(account_bal);
                } catch (const ApiError& exc) {
                    note_failure("account=" + account_id + " (" + inst_name + ")", exc.status(),
                                 exc.detail());
                    std::cout << "  Skipped: " << exc.detail() << "\n";
                }
            }
        }

        std::cout << "Fetched identity records: " << raw_identities.size() << "\n";

        // Hard-fail only when nothing was gathered (07_fetch parity); otherwise
        // report the skipped enrollments and persist the healthy accounts.
        if (raw_identities.empty()) {
            if (!failures.empty()) {
                const auto& first = failures.front();
                std::cerr << "teller_fetch failed (" << first.status << "): " << first.detail << "\n";
                if (saw_disconnected) {
                    std::cerr << "Reconnect via the classy macOS app "
                                 "(../classy/06_run_classification_macos_ui.sh, Connect tab) to repair.\n";
                }
                return 1;
            }
            std::cout << "No accounts found for the requested scope.\n";
        }
        for (const auto& f : failures) {
            std::cerr << "WARNING: skipped " << f.scope << " (status " << f.status << "): " << f.detail
                      << "\n";
        }
        if (saw_disconnected) {
            std::cerr << "One or more enrollments are disconnected. Reconnect them via the classy "
                         "macOS app (../classy/06_run_classification_macos_ui.sh, Connect tab), then "
                         "rerun to ingest them.\n";
        }

        if (!dump_payload_path.empty()) {
            std::ofstream out(dump_payload_path);
            if (!out) throw ApiError(500, "cannot write payload dump: " + dump_payload_path);
            out << json{{"identities", raw_identities},
                        {"transactions_by_account", txns_by_account},
                        {"balances_by_account", balances_by_account}}
                       .dump(2)
                << "\n";
            std::cout << "Wrote fetched payload to " << dump_payload_path << "\n";
        }

        if (dry_run) {
            std::cout << "Dry run complete. No database changes were made.\n";
            return 0;
        }

        const DbProfile profile = resolve_profile();
        std::unique_ptr<db::Db> database = db::open_from_profile(profile);
        persist::persist_all(*database, raw_identities, txns_by_account, balances_by_account);
        std::cout << "Persisted to database (" << raw_identities.size() << " account(s)"
                  << (failures.empty() ? "" : ", " + std::to_string(failures.size()) + " skipped")
                  << ").\n";
        return 0;
    } catch (const ApiError& exc) {
        std::cerr << "teller_fetch failed (" << exc.status() << "): " << exc.detail() << "\n";
        return 1;
    } catch (const std::exception& exc) {
        std::cerr << "teller_fetch failed: " << exc.what() << "\n";
        return 1;
    }
}
// NOLINTEND(concurrency-mt-unsafe,bugprone-empty-catch,bugprone-exception-escape)
