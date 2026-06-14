// NOLINTBEGIN(cert-err33-c,bugprone-easily-swappable-parameters,bugprone-unchecked-optional-access,bugprone-unchecked-string-to-number-conversion,cert-err34-c)
#include "tellercore/db_postgres.hpp"

#include <libpq-fe.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <stdexcept>
#include <utility>

namespace tellercore::db {

namespace {

// Postgres type OIDs (pg_type.h) needed to coerce text results back into the
// Value variant with the same shapes the SQLite backend produces.
constexpr unsigned int kOidBool = 16;
constexpr unsigned int kOidInt8 = 20;
constexpr unsigned int kOidInt2 = 21;
constexpr unsigned int kOidInt4 = 23;
constexpr unsigned int kOidFloat4 = 700;
constexpr unsigned int kOidFloat8 = 701;
constexpr unsigned int kOidNumeric = 1700;
constexpr unsigned int kOidTimestamp = 1114;
constexpr unsigned int kOidTimestamptz = 1184;

// #R001: Traceability for function `is_ident_char`.
bool is_ident_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

} // namespace

// #R001: Traceability for function `translate_named_params`.
TranslatedSql translate_named_params(const std::string& sql) {
    TranslatedSql out;
    out.sql.reserve(sql.size() + 16);
    std::map<std::string, size_t> seen;
    bool in_literal = false;
    for (size_t i = 0; i < sql.size(); ++i) {
        const char c = sql[i];
        if (in_literal) {
            out.sql += c;
            if (c == '\'') in_literal = false; // '' escapes re-enter on next quote
            continue;
        }
        if (c == '\'') {
            in_literal = true;
            out.sql += c;
            continue;
        }
        const bool starts_param = c == ':' && i + 1 < sql.size() &&
                                  (is_ident_char(sql[i + 1]) && !(sql[i + 1] >= '0' && sql[i + 1] <= '9')) &&
                                  (i == 0 || (sql[i - 1] != ':' && !is_ident_char(sql[i - 1])));
        if (!starts_param) {
            out.sql += c;
            continue;
        }
        size_t end = i + 1;
        while (end < sql.size() && is_ident_char(sql[end])) ++end;
        const std::string name = sql.substr(i + 1, end - i - 1);
        auto it = seen.find(name);
        size_t index;
        if (it == seen.end()) {
            out.param_names.push_back(name);
            index = out.param_names.size();
            seen.emplace(name, index);
        } else {
            index = it->second;
        }
        out.sql += "$" + std::to_string(index);
        i = end - 1;
    }
    return out;
}

namespace {

// Shortest decimal text that round-trips to the same double, so numeric SQL
// comparisons see the intended value without 17-digit noise.
// #R001: Traceability for function `double_to_text`.
std::string double_to_text(double value) {
    char buf[64];
    for (int precision : {15, 16, 17}) {
        std::snprintf(buf, sizeof(buf), "%.*g", precision, value);
        if (std::strtod(buf, nullptr) == value) break;
    }
    return buf;
}

// #R001: Traceability for function `quote_identifier`.
std::string quote_identifier(const std::string& ident) {
    std::string out = "\"";
    for (char c : ident) {
        out += c;
        if (c == '"') out += '"';
    }
    out += "\"";
    return out;
}

// "teller,classy,matchy" -> "\"teller\", \"classy\", \"matchy\"" (teller_db.py parity).
// #R001: Traceability for function `quoted_search_path`.
std::string quoted_search_path(const std::string& search_path) {
    std::string out;
    std::string part;
    auto flush = [&] {
        const auto begin = part.find_first_not_of(" \t");
        if (begin == std::string::npos) {
            part.clear();
            return;
        }
        const auto end = part.find_last_not_of(" \t");
        if (!out.empty()) out += ", ";
        out += quote_identifier(part.substr(begin, end - begin + 1));
        part.clear();
    };
    for (char c : search_path) {
        if (c == ',') {
            flush();
        } else {
            part += c;
        }
    }
    flush();
    return out;
}

// #R001: Traceability for function `throw_pg_error`.
[[noreturn]] void throw_pg_error(PGconn* conn, PGresult* result, const std::string& context) {
    std::string detail;
    if (result) {
        const char* message = PQresultErrorMessage(result);
        if (message) detail = message;
        PQclear(result);
    }
    if (detail.empty() && conn) {
        const char* message = PQerrorMessage(conn);
        if (message) detail = message;
    }
    while (!detail.empty() && (detail.back() == '\n' || detail.back() == '\r')) detail.pop_back();
    throw std::runtime_error(context + ": " + (detail.empty() ? "unknown error" : detail));
}

// Postgres renders timestamptz as "YYYY-MM-DD HH:MM:SS[.ffffff]+00" under the
// UTC session timezone. Strip the offset so timestamps look like the SQLite
// backend's naive-UTC text and json_io::to_utc_iso8601 normalizes identically.
// #R001: Traceability for function `strip_utc_offset`.
std::string strip_utc_offset(std::string text) {
    if (text.size() > 19) {
        for (size_t i = 19; i < text.size(); ++i) {
            if (text[i] == '+' || text[i] == '-') {
                text.erase(i);
                break;
            }
        }
    }
    return text;
}

// #R001: Traceability for function `value_from_field`.
Value value_from_field(unsigned int oid, const char* text) {
    const std::string s = text ? text : "";
    switch (oid) {
        case kOidBool:
            return static_cast<int64_t>((!s.empty() && (s[0] == 't' || s[0] == 'T' || s[0] == '1')) ? 1 : 0);
        case kOidInt2:
        case kOidInt4:
        case kOidInt8:
            try {
                return static_cast<int64_t>(std::stoll(s));
            } catch (...) {
                return s;
            }
        case kOidFloat4:
        case kOidFloat8:
        case kOidNumeric:
            try {
                return std::stod(s);
            } catch (...) {
                return s;
            }
        case kOidTimestamp:
        case kOidTimestamptz:
            return strip_utc_offset(s);
        default:
            return s;
    }
}

// #R001: Traceability for function `conninfo_from_config`.
std::string conninfo_from_config(const PostgresConfig& config) {
    auto quote = [](const std::string& value) {
        std::string out = "'";
        for (char c : value) {
            if (c == '\\' || c == '\'') out += '\\';
            out += c;
        }
        out += "'";
        return out;
    };
    std::string conninfo = "host=" + quote(config.host) + " port=" + std::to_string(config.port) +
                           " dbname=" + quote(config.dbname) + " user=" + quote(config.user);
    if (!config.password.empty()) conninfo += " password=" + quote(config.password);
    // teller_db.py parity: sslmode is forwarded only when set and not "disable".
    if (!config.sslmode.empty() && config.sslmode != "disable") {
        conninfo += " sslmode=" + quote(config.sslmode);
    }
    return conninfo;
}

} // namespace

// #R001: Traceability for function `PostgresDb`.
PostgresDb::PostgresDb(const PostgresConfig& config) {
    open(conninfo_from_config(config), config.search_path, config.runtime_role);
}

// #R001: Traceability for function `PostgresDb`.
PostgresDb::PostgresDb(const std::string& conninfo, const std::string& search_path) {
    open(conninfo, search_path, "");
}

// #R001: Traceability for function `PostgresDb`.
PostgresDb::~PostgresDb() {
    if (conn_) PQfinish(conn_);
}

// #R001: Traceability for function `open`.
void PostgresDb::open(const std::string& conninfo, const std::string& search_path,
                      const std::string& runtime_role) {
    conn_ = PQconnectdb(conninfo.c_str());
    if (!conn_ || PQstatus(conn_) != CONNECTION_OK) {
        std::string detail = conn_ ? PQerrorMessage(conn_) : "PQconnectdb returned null";
        if (conn_) {
            PQfinish(conn_);
            conn_ = nullptr;
        }
        while (!detail.empty() && (detail.back() == '\n' || detail.back() == '\r')) detail.pop_back();
        throw std::runtime_error("postgres connect failed: " + detail);
    }
    try {
        session_setup(search_path, runtime_role);
    } catch (...) {
        PQfinish(conn_);
        conn_ = nullptr;
        throw;
    }
}

// #R001: Traceability for function `session_setup`.
void PostgresDb::session_setup(const std::string& search_path, const std::string& runtime_role) {
    // UTC session timezone keeps timestamptz text output parity with the
    // naive-UTC timestamps the SQLite backend stores.
    execute_script("SET TIME ZONE 'UTC'");
    if (!search_path.empty()) {
        execute_script("SET search_path TO " + quoted_search_path(search_path));
    }
    if (!runtime_role.empty()) {
        execute_script("SET ROLE " + quote_identifier(runtime_role));
    }
}

// #R001: Traceability for function `execute_script`.
void PostgresDb::execute_script(const std::string& sql) {
    PGresult* result = PQexec(conn_, sql.c_str());
    const auto status = result ? PQresultStatus(result) : PGRES_FATAL_ERROR;
    if (status != PGRES_COMMAND_OK && status != PGRES_TUPLES_OK && status != PGRES_EMPTY_QUERY) {
        throw_pg_error(conn_, result, "execute_script failed");
    }
    PQclear(result);
}

namespace {

struct ExecResult {
    PGresult* result = nullptr;
    // #R001: Traceability for function `ExecResult`.
    ~ExecResult() {
        if (result) PQclear(result);
    }
};

} // namespace

// #R001: Traceability for function `query`.
std::vector<Row> PostgresDb::query(const std::string& sql, const Params& params) {
    const TranslatedSql translated = translate_named_params(sql);

    const size_t n_params = translated.param_names.size();
    std::vector<std::optional<std::string>> storage(n_params);
    for (size_t i = 0; i < n_params; ++i) {
        auto it = params.find(translated.param_names[i]);
        // Unsupplied parameters bind as NULL, mirroring SQLite's default.
        if (it == params.end() || std::holds_alternative<std::monostate>(it->second)) continue;
        if (auto* iv = std::get_if<int64_t>(&it->second)) {
            storage[i] = std::to_string(*iv);
        } else if (auto* dv = std::get_if<double>(&it->second)) {
            storage[i] = double_to_text(*dv);
        } else {
            storage[i] = std::get<std::string>(it->second);
        }
    }
    std::vector<const char*> values(n_params, nullptr);
    for (size_t i = 0; i < n_params; ++i) {
        if (storage[i].has_value()) values[i] = storage[i]->c_str();
    }

    ExecResult exec;
    exec.result = PQexecParams(conn_, translated.sql.c_str(), static_cast<int>(values.size()),
                               nullptr, values.data(), nullptr, nullptr, /*text format*/ 0);
    const auto status = exec.result ? PQresultStatus(exec.result) : PGRES_FATAL_ERROR;
    if (status != PGRES_TUPLES_OK && status != PGRES_COMMAND_OK) {
        PGresult* result = exec.result;
        exec.result = nullptr;
        throw_pg_error(conn_, result, "query failed for: " + sql.substr(0, 120));
    }

    std::vector<Row> rows;
    if (status == PGRES_TUPLES_OK) {
        const int n_rows = PQntuples(exec.result);
        const int n_cols = PQnfields(exec.result);
        rows.reserve(static_cast<size_t>(n_rows));
        for (int r = 0; r < n_rows; ++r) {
            Row row;
            for (int c = 0; c < n_cols; ++c) {
                const char* name = PQfname(exec.result, c);
                Value value;
                if (PQgetisnull(exec.result, r, c)) {
                    value = std::monostate{};
                } else {
                    value = value_from_field(PQftype(exec.result, c), PQgetvalue(exec.result, r, c));
                }
                row.columns.emplace(name ? name : "", std::move(value));
            }
            rows.push_back(std::move(row));
        }
    }
    last_affected_ = 0;
    if (const char* tuples = exec.result ? PQcmdTuples(exec.result) : nullptr) {
        if (*tuples) last_affected_ = std::atoi(tuples);
    }
    return rows;
}

// #R001: Traceability for function `query_one`.
std::optional<Row> PostgresDb::query_one(const std::string& sql, const Params& params) {
    auto rows = query(sql, params);
    if (rows.empty()) return std::nullopt;
    return std::move(rows.front());
}

// #R001: Traceability for function `execute`.
int PostgresDb::execute(const std::string& sql, const Params& params) {
    query(sql, params);
    return last_affected_;
}

// #R001: Traceability for function `begin`.
void PostgresDb::begin() {
    if (in_txn_) return;
    execute_script("BEGIN");
    in_txn_ = true;
}

// #R001: Traceability for function `commit`.
void PostgresDb::commit() {
    if (!in_txn_) return;
    execute_script("COMMIT");
    in_txn_ = false;
}

// #R001: Traceability for function `rollback`.
void PostgresDb::rollback() {
    if (!in_txn_) return;
    execute_script("ROLLBACK");
    in_txn_ = false;
}

} // namespace tellercore::db
// NOLINTEND(cert-err33-c,bugprone-easily-swappable-parameters,bugprone-unchecked-optional-access,bugprone-unchecked-string-to-number-conversion,cert-err34-c)
