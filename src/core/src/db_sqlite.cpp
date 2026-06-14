#include "tellercore/db.hpp"

#include <sqlcipher/sqlite3.h>

#include <filesystem>
#include <stdexcept>

namespace tellercore::db {

namespace {

std::string escape_sqlite_literal(const std::string& value) {
    std::string out;
    out.reserve(value.size());
    for (char c : value) {
        out += c;
        if (c == '\'') out += '\'';
    }
    return out;
}

[[noreturn]] void throw_sqlite_error(sqlite3* conn, const std::string& context) {
    throw std::runtime_error(context + ": " + (conn ? sqlite3_errmsg(conn) : "unknown error"));
}

} // namespace

class Statement {
public:
    Statement(sqlite3* conn, const std::string& sql) : conn_(conn), sql_(sql.substr(0, 160)) {
        if (sqlite3_prepare_v2(conn, sql.c_str(), -1, &stmt_, nullptr) != SQLITE_OK) {
            throw_sqlite_error(conn, "prepare failed for: " + sql.substr(0, 120));
        }
    }
    ~Statement() {
        if (stmt_) sqlite3_finalize(stmt_);
    }

    void bind(const Params& params) {
        for (const auto& [name, value] : params) {
            const std::string key = ":" + name;
            const int index = sqlite3_bind_parameter_index(stmt_, key.c_str());
            if (index == 0) continue; // SQL may not reference every supplied param
            int rc;
            if (std::holds_alternative<std::monostate>(value)) {
                rc = sqlite3_bind_null(stmt_, index);
            } else if (auto* i = std::get_if<int64_t>(&value)) {
                rc = sqlite3_bind_int64(stmt_, index, *i);
            } else if (auto* d = std::get_if<double>(&value)) {
                rc = sqlite3_bind_double(stmt_, index, *d);
            } else {
                const auto& s = std::get<std::string>(value);
                rc = sqlite3_bind_text(stmt_, index, s.c_str(), static_cast<int>(s.size()),
                                       SQLITE_TRANSIENT);
            }
            if (rc != SQLITE_OK) throw_sqlite_error(conn_, "bind failed for " + name);
        }
    }

    // Returns true while rows remain.
    bool step() {
        const int rc = sqlite3_step(stmt_);
        if (rc == SQLITE_ROW) return true;
        if (rc == SQLITE_DONE) return false;
        throw_sqlite_error(conn_, "step failed for: " + sql_);
    }

    Row current_row() const {
        Row row;
        const int count = sqlite3_column_count(stmt_);
        for (int i = 0; i < count; ++i) {
            const char* name = sqlite3_column_name(stmt_, i);
            Value value;
            switch (sqlite3_column_type(stmt_, i)) {
                case SQLITE_INTEGER: value = sqlite3_column_int64(stmt_, i); break;
                case SQLITE_FLOAT: value = sqlite3_column_double(stmt_, i); break;
                case SQLITE_NULL: value = std::monostate{}; break;
                default: {
                    const unsigned char* t = sqlite3_column_text(stmt_, i);
                    value = std::string(t ? reinterpret_cast<const char*>(t) : "");
                    break;
                }
            }
            row.columns.emplace(name ? name : "", std::move(value));
        }
        return row;
    }

private:
    sqlite3* conn_;
    sqlite3_stmt* stmt_ = nullptr;
    std::string sql_;
};

SqliteDb::SqliteDb(const std::string& sqlite_path, const std::string& sqlcipher_key) {
    if (sqlite3_open(":memory:", &conn_) != SQLITE_OK) {
        throw_sqlite_error(conn_, "open :memory: failed");
    }
    const std::string escaped_key = escape_sqlite_literal(sqlcipher_key);
    char* errmsg = nullptr;
    const std::string key_pragma = "PRAGMA key = '" + escaped_key + "'";
    if (sqlite3_exec(conn_, key_pragma.c_str(), nullptr, nullptr, &errmsg) != SQLITE_OK) {
        const std::string detail = errmsg ? errmsg : "unknown";
        sqlite3_free(errmsg);
        throw std::runtime_error("PRAGMA key failed: " + detail);
    }
    if (!sqlite_path.empty()) {
        const std::string attach = "ATTACH DATABASE '" + escape_sqlite_literal(sqlite_path) +
                                   "' AS teller KEY '" + escaped_key + "'";
        if (sqlite3_exec(conn_, attach.c_str(), nullptr, nullptr, &errmsg) != SQLITE_OK) {
            const std::string detail = errmsg ? errmsg : "unknown";
            sqlite3_free(errmsg);
            throw std::runtime_error("ATTACH DATABASE failed: " + detail);
        }
    }
    if (sqlite3_exec(conn_, "PRAGMA foreign_keys = ON", nullptr, nullptr, nullptr) != SQLITE_OK) {
        throw_sqlite_error(conn_, "PRAGMA foreign_keys failed");
    }
    sqlite3_busy_timeout(conn_, 5000);
}

SqliteDb::~SqliteDb() {
    if (conn_) sqlite3_close_v2(conn_);
}

void SqliteDb::bootstrap_file(const std::string& sqlite_path, const std::string& sqlcipher_key,
                              const std::string& ddl_script) {
    // First-run: SQLite cannot create intermediate directories itself.
    const auto parent = std::filesystem::path(sqlite_path).parent_path();
    if (!parent.empty()) {
        std::error_code ec;
        std::filesystem::create_directories(parent, ec);
    }
    sqlite3* conn = nullptr;
    if (sqlite3_open(sqlite_path.c_str(), &conn) != SQLITE_OK) {
        const std::string detail = conn ? sqlite3_errmsg(conn) : "unknown error";
        sqlite3_close_v2(conn);
        throw std::runtime_error("open " + sqlite_path + " failed: " + detail);
    }
    char* errmsg = nullptr;
    const std::string key_pragma = "PRAGMA key = '" + escape_sqlite_literal(sqlcipher_key) + "'";
    if (sqlite3_exec(conn, key_pragma.c_str(), nullptr, nullptr, &errmsg) != SQLITE_OK) {
        const std::string detail = errmsg ? errmsg : "unknown";
        sqlite3_free(errmsg);
        sqlite3_close_v2(conn);
        throw std::runtime_error("PRAGMA key failed: " + detail);
    }
    if (sqlite3_exec(conn, ddl_script.c_str(), nullptr, nullptr, &errmsg) != SQLITE_OK) {
        const std::string detail = errmsg ? errmsg : "unknown";
        sqlite3_free(errmsg);
        sqlite3_close_v2(conn);
        throw std::runtime_error("bootstrap DDL failed: " + detail);
    }
    sqlite3_close_v2(conn);
}

void SqliteDb::execute_script(const std::string& sql) {
    char* errmsg = nullptr;
    if (sqlite3_exec(conn_, sql.c_str(), nullptr, nullptr, &errmsg) != SQLITE_OK) {
        const std::string detail = errmsg ? errmsg : "unknown";
        sqlite3_free(errmsg);
        throw std::runtime_error("execute_script failed: " + detail);
    }
}

std::unique_ptr<Statement> SqliteDb::prepare(const std::string& sql, const Params& params) {
    auto stmt = std::make_unique<Statement>(conn_, sql);
    stmt->bind(params);
    return stmt;
}

std::vector<Row> SqliteDb::query(const std::string& sql, const Params& params) {
    auto stmt = prepare(sql, params);
    std::vector<Row> rows;
    while (stmt->step()) rows.push_back(stmt->current_row());
    return rows;
}

std::optional<Row> SqliteDb::query_one(const std::string& sql, const Params& params) {
    auto stmt = prepare(sql, params);
    if (!stmt->step()) return std::nullopt;
    return stmt->current_row();
}

int SqliteDb::execute(const std::string& sql, const Params& params) {
    auto stmt = prepare(sql, params);
    while (stmt->step()) {
    }
    return sqlite3_changes(conn_);
}

void SqliteDb::begin() {
    if (in_txn_) return;
    execute("BEGIN IMMEDIATE");
    in_txn_ = true;
}

void SqliteDb::commit() {
    if (!in_txn_) return;
    execute("COMMIT");
    in_txn_ = false;
}

void SqliteDb::rollback() {
    if (!in_txn_) return;
    execute("ROLLBACK");
    in_txn_ = false;
}

int64_t SqliteDb::last_insert_rowid() const { return sqlite3_last_insert_rowid(conn_); }

} // namespace tellercore::db
