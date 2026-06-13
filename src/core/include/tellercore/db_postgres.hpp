#pragma once

#include <string>

#include "tellercore/db.hpp"

typedef struct pg_conn PGconn;

namespace tellercore::db {

// :name -> $n rewrite result. Exposed for unit tests; PostgresDb uses it for
// every statement (libpq has no named-parameter support).
struct TranslatedSql {
    std::string sql;                      // :name placeholders rewritten to $n
    std::vector<std::string> param_names; // 1-based order of $n placeholders
};

// Rewrites :name parameters to positional $n placeholders. Single-quoted
// literals are skipped; repeated names map to the same placeholder, matching
// SQLite bind-by-name semantics.
TranslatedSql translate_named_params(const std::string& sql);

// Connection settings for the libpq backend. Mirrors the connect_args the
// retired Python teller_db.get_engine() passed to psycopg2 plus the
// connect-time session setup (search_path, optional SET ROLE for local
// Postgres; Supabase-managed connections skip the role switch).
struct PostgresConfig {
    std::string host;
    int port = 5432;
    std::string dbname;
    std::string user;
    std::string password;
    // Empty or "disable" omits sslmode from the conninfo (local default);
    // Supabase-managed profiles resolve to "require".
    std::string sslmode;
    std::string search_path = "teller,classy,matchy";
    std::string runtime_role; // SET ROLE when non-empty (local target only)
};

// RAII libpq connection speaking the same Db interface as SQLCipher. Named
// parameters (:name) are translated to positional $n placeholders; results
// come back as text and are coerced into the Value variant by column OID so
// Row getters behave identically across backends.
class PostgresDb final : public Db {
public:
    explicit PostgresDb(const PostgresConfig& config);
    // Raw libpq conninfo string (e.g. "host=... dbname=..."); used by the
    // oracle runner and Postgres-gated tests. Session setup still applies.
    explicit PostgresDb(const std::string& conninfo,
                        const std::string& search_path = "teller,classy,matchy");
    ~PostgresDb() override;

    Dialect dialect() const noexcept override { return Dialect::kPostgres; }

    void execute_script(const std::string& sql) override;

    std::vector<Row> query(const std::string& sql, const Params& params = {}) override;
    std::optional<Row> query_one(const std::string& sql, const Params& params = {}) override;
    int execute(const std::string& sql, const Params& params = {}) override;

    void begin() override;
    void commit() override;
    void rollback() override;

private:
    void open(const std::string& conninfo, const std::string& search_path,
              const std::string& runtime_role);
    void session_setup(const std::string& search_path, const std::string& runtime_role);

    PGconn* conn_ = nullptr;
    int last_affected_ = 0;
};

} // namespace tellercore::db
