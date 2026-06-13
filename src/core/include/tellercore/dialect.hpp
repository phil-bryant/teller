#pragma once

namespace tellercore {

// SQL dialect of the active backend. Mirrors the retired Python `_is_sqlite_session`
// branch in teller_persist.py: SQLite stores money as integer cents and reaches
// teller.* tables through the ATTACH alias; Postgres (local or Supabase-managed)
// uses the canonical schema-qualified names and decimal money.
enum class Dialect {
    kSqlite,
    kPostgres,
};

} // namespace tellercore
