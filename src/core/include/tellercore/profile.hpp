// #R001: Module-level traceability anchor.
#pragma once

#include <stdexcept>
#include <string>

namespace tellercore {

// Resolution of the teller DB profile, C++ port of teller_db_profile.py.
// Three targets, same as the Python stack:
//   - sqlite : per-device SQLCipher file (path + key)
//   - local  : localhost PostgreSQL (optional SET ROLE runtime role)
//   - managed: Supabase-hosted PostgreSQL (TLS required by default)
//
// Resolution order mirrors teller_db_profile.py:
//   1. TELLER_DB_SQLITE_PATH / TELLER_DB_SQLCIPHER_KEY env overrides force the
//      sqlite target outright.
//   2. Profile file search order: $TELLER_DB_PROFILE_FILE, ~/.teller/db_profiles.json,
//      ./config/db-profiles.local.json, ./config/db-profiles.json.
//   3. ~/.env fallback lines of the form "<item>.<field>=..." supply connection
//      fields (libonepsa stays a Python-side concern; ~/.env is the documented
//      fallback for the C++ core).
//   4. TELLER_DB_HOST/PORT/NAME/USER/PASSWORD/ROLE/SSLMODE/SEARCH_PATH env vars
//      override individual Postgres fields on top of the profile.
enum class DbTarget {
    kLocal,
    kManaged,
    kSqlite,
};

struct DbProfile {
    std::string name;
    DbTarget target = DbTarget::kLocal;

    // Postgres targets (local + managed).
    std::string host;
    int port = 5432;
    std::string dbname;
    std::string user;
    std::string password;
    std::string search_path;
    std::string runtime_role;
    std::string sslmode;

    // Sqlite target.
    std::string sqlite_path;
    std::string sqlcipher_key;
};

// Kept for the sqlite-only call sites (bootstrap paths, tests).
struct SqliteProfile {
    std::string name;
    std::string sqlite_path;
    std::string sqlcipher_key;
};

class ProfileError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

DbProfile resolve_profile();

// Resolves the profile and requires the sqlite target; throws ProfileError when
// the active profile targets Postgres.
SqliteProfile resolve_sqlite_profile();

} // namespace tellercore
