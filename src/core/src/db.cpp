#include "tellercore/db.hpp"

#include <stdexcept>

#include "tellercore/profile.hpp"

#ifdef TELLERCORE_ENABLE_POSTGRES
#include "tellercore/db_postgres.hpp"
#endif

namespace tellercore::db {

bool Row::has(const std::string& name) const { return columns.count(name) > 0; }

bool Row::is_null(const std::string& name) const {
    auto it = columns.find(name);
    return it == columns.end() || std::holds_alternative<std::monostate>(it->second);
}

std::optional<int64_t> Row::get_int(const std::string& name) const {
    auto it = columns.find(name);
    if (it == columns.end()) return std::nullopt;
    if (auto* i = std::get_if<int64_t>(&it->second)) return *i;
    if (auto* d = std::get_if<double>(&it->second)) return static_cast<int64_t>(*d);
    if (auto* s = std::get_if<std::string>(&it->second)) {
        try {
            return std::stoll(*s);
        } catch (...) {
            return std::nullopt;
        }
    }
    return std::nullopt;
}

std::optional<double> Row::get_double(const std::string& name) const {
    auto it = columns.find(name);
    if (it == columns.end()) return std::nullopt;
    if (auto* d = std::get_if<double>(&it->second)) return *d;
    if (auto* i = std::get_if<int64_t>(&it->second)) return static_cast<double>(*i);
    if (auto* s = std::get_if<std::string>(&it->second)) {
        try {
            return std::stod(*s);
        } catch (...) {
            return std::nullopt;
        }
    }
    return std::nullopt;
}

std::optional<std::string> Row::get_text(const std::string& name) const {
    auto it = columns.find(name);
    if (it == columns.end() || std::holds_alternative<std::monostate>(it->second)) return std::nullopt;
    if (auto* s = std::get_if<std::string>(&it->second)) return *s;
    if (auto* i = std::get_if<int64_t>(&it->second)) return std::to_string(*i);
    return std::to_string(std::get<double>(it->second));
}

std::unique_ptr<Db> open_from_profile(const DbProfile& profile) {
    if (profile.target == DbTarget::kSqlite) {
        return std::make_unique<SqliteDb>(profile.sqlite_path, profile.sqlcipher_key);
    }
#ifdef TELLERCORE_ENABLE_POSTGRES
    PostgresConfig config;
    config.host = profile.host;
    config.port = profile.port;
    config.dbname = profile.dbname;
    config.user = profile.user;
    config.password = profile.password;
    config.sslmode = profile.sslmode;
    config.search_path = profile.search_path;
    // teller_db.py parity: SET ROLE applies to local Postgres only; Supabase
    // (managed) connections authenticate as the runtime user directly.
    config.runtime_role = profile.target == DbTarget::kLocal ? profile.runtime_role : "";
    return std::make_unique<PostgresDb>(config);
#else
    throw std::runtime_error(
        "DB profile '" + profile.name + "' targets Postgres, but this build of the core was "
        "compiled without Postgres support (TELLERCORE_ENABLE_POSTGRES=OFF). Select the sqlite "
        "profile (TELLER_DB_PROFILE=sqlite) or rebuild with libpq.");
#endif
}

Transaction::Transaction(Db& db) : db_(db) { db_.begin(); }

Transaction::~Transaction() {
    if (!done_) db_.rollback();
}

void Transaction::commit() {
    db_.commit();
    done_ = true;
}

} // namespace tellercore::db
