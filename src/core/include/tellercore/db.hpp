#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "tellercore/dialect.hpp"

struct sqlite3;
struct sqlite3_stmt;

namespace tellercore {
struct DbProfile;
}

namespace tellercore::db {

// Null / integer / real / text. Booleans bind as integers (SQLite semantics;
// the Postgres backend coerces them through type inference).
using Value = std::variant<std::monostate, int64_t, double, std::string>;
using Params = std::map<std::string, Value>;

struct Row {
    std::map<std::string, Value> columns;

    bool has(const std::string& name) const;
    bool is_null(const std::string& name) const;
    std::optional<int64_t> get_int(const std::string& name) const;
    std::optional<double> get_double(const std::string& name) const;
    std::optional<std::string> get_text(const std::string& name) const;
};

// Abstract backend connection. The persist layer addresses this interface only;
// the concrete dialect drives money storage (cents vs decimal) decisions.
class Db {
public:
    // #R001: Traceability for function `Db`.
    virtual ~Db() = default;

    // #R001: Traceability for function `Db`.
    Db(const Db&) = delete;
    // #R001: Traceability for function `<anonymous>`.
    Db& operator=(const Db&) = delete;

    virtual Dialect dialect() const noexcept = 0;

    // Runs a multi-statement script (DDL bootstrap, seeds).
    virtual void execute_script(const std::string& sql) = 0;

    virtual std::vector<Row> query(const std::string& sql, const Params& params = {}) = 0;
    virtual std::optional<Row> query_one(const std::string& sql, const Params& params = {}) = 0;
    // Returns number of affected rows.
    virtual int execute(const std::string& sql, const Params& params = {}) = 0;

    virtual void begin() = 0;
    virtual void commit() = 0;
    virtual void rollback() = 0;
    // #R001: Traceability for function `in_transaction`.
    bool in_transaction() const noexcept { return in_txn_; }

protected:
    // #R001: Traceability for function `Db`.
    Db() = default;
    bool in_txn_ = false;
};

class Statement;

// RAII SQLCipher connection. Replicates teller_db.get_engine() sqlite semantics:
// open :memory: with PRAGMA key, ATTACH the database file AS teller with the same
// key, enable foreign keys. All owned-schema SQL then addresses teller.* tables.
class SqliteDb final : public Db {
public:
    // Opens via PRAGMA key + ATTACH ... AS teller. Throws std::runtime_error on failure.
    SqliteDb(const std::string& sqlite_path, const std::string& sqlcipher_key);

    // Opens sqlite_path directly as the main schema (no ATTACH) and runs the
    // canonical DDL script against it. Used to bootstrap fixture/new databases,
    // mirroring teller's deploy path where unqualified DDL targets the file.
    static void bootstrap_file(const std::string& sqlite_path, const std::string& sqlcipher_key,
                               const std::string& ddl_script);
    ~SqliteDb() override;

    // #R001: Traceability for function `dialect`.
    Dialect dialect() const noexcept override { return Dialect::kSqlite; }

    void execute_script(const std::string& sql) override;

    std::vector<Row> query(const std::string& sql, const Params& params = {}) override;
    std::optional<Row> query_one(const std::string& sql, const Params& params = {}) override;
    int execute(const std::string& sql, const Params& params = {}) override;

    void begin() override;
    void commit() override;
    void rollback() override;

    int64_t last_insert_rowid() const;

    // #R001: Traceability for function `raw`.
    sqlite3* raw() const noexcept { return conn_; }

private:
    std::unique_ptr<Statement> prepare(const std::string& sql, const Params& params);
    sqlite3* conn_ = nullptr;
};

// Opens the backend selected by the resolved teller DB profile: SQLCipher for
// sqlite targets, libpq for local Postgres / Supabase-managed targets. Throws
// std::runtime_error when the build lacks Postgres support and the profile
// requires it.
std::unique_ptr<Db> open_from_profile(const DbProfile& profile);

// Scoped transaction: commits on success(), rolls back on destruction otherwise.
class Transaction {
public:
    explicit Transaction(Db& db);
    ~Transaction();
    void commit();

private:
    Db& db_;
    bool done_ = false;
};

} // namespace tellercore::db
