// NOLINTBEGIN(bugprone-throwing-static-initialization,cert-err58-cpp,concurrency-mt-unsafe,bugprone-empty-catch)
#include "tellercore/profile.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <vector>

#include <nlohmann/json.hpp>

#include "tellercore/onepsa.hpp"

namespace tellercore {

namespace {

namespace fs = std::filesystem;
using nlohmann::json;

const std::set<std::string> kAllowedSslmodes = {"disable",  "allow",     "prefer",
                                                "require",  "verify-ca", "verify-full"};

// #R001: Traceability for function `env_or_empty`.
std::string env_or_empty(const char* name) {
    const char* value = std::getenv(name);
    return value ? std::string(value) : std::string();
}

// #R001: Traceability for function `trimmed`.
std::string trimmed(const std::string& s) {
    const auto begin = s.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) return {};
    const auto end = s.find_last_not_of(" \t\r\n");
    return s.substr(begin, end - begin + 1);
}

// #R001: Traceability for function `home_dir`.
fs::path home_dir() {
    const std::string home = env_or_empty("HOME");
    return home.empty() ? fs::path("/") : fs::path(home);
}

// #R001: Traceability for function `candidate_profile_paths`.
std::vector<fs::path> candidate_profile_paths() {
    std::vector<fs::path> paths;
    const std::string explicit_path = trimmed(env_or_empty("TELLER_DB_PROFILE_FILE"));
    if (!explicit_path.empty()) paths.emplace_back(explicit_path);
    paths.emplace_back(home_dir() / ".teller" / "db_profiles.json");
    paths.emplace_back(fs::current_path() / "config" / "db-profiles.local.json");
    paths.emplace_back(fs::current_path() / "config" / "db-profiles.json");
    return paths;
}

// ~/.env fallback lines: "<item>.<field>=<value>" (same parsing as Python).
// #R001: Traceability for function `read_env_file_fields`.
std::map<std::string, std::string> read_env_file_fields(const std::string& item) {
    std::map<std::string, std::string> fields;
    std::ifstream in(home_dir() / ".env");
    if (!in.is_open()) return fields;
    const std::string prefix = item + ".";
    std::string raw_line;
    while (std::getline(in, raw_line)) {
        const std::string line = trimmed(raw_line);
        if (line.empty() || line[0] == '#') continue;
        if (line.rfind(prefix, 0) != 0) continue;
        const std::string rest = line.substr(prefix.size());
        const auto eq = rest.find('=');
        if (eq == std::string::npos) continue;
        const std::string field_name = trimmed(rest.substr(0, eq));
        const std::string value = trimmed(rest.substr(eq + 1));
        if (!field_name.empty()) fields[field_name] = value;
    }
    return fields;
}

// Mirrors teller_db_profile._CONNECTION_FIELDS (password resolved separately).
const std::vector<std::string> kConnectionFields = {
    "host", "port",         "database", "username", "schema",
    "runtime_role", "target", "sslmode", "sqlcipher_key"};

// teller_db_profile._fetch_record_from_onepsa parity: read connection fields
// from 1psa first; if 1psa yields no host (unavailable or rate-limited), fall
// back to the ~/.env item fields; otherwise use the 1psa values.
// #R001: Traceability for function `resolve_item_fields`.
std::map<std::string, std::string> resolve_item_fields(const std::string& item) {
    std::map<std::string, std::string> fields = onepsa::read_fields(item, kConnectionFields);
    auto host = fields.find("host");
    if (host != fields.end() && !host->second.empty()) return fields;
    std::map<std::string, std::string> env_fields = read_env_file_fields(item);
    if (!env_fields.empty()) return env_fields;
    return fields;
}

// teller_db._read_password parity: 1psa strict lookup, then ~/.env "password".
// TELLER_DB_PASSWORD is applied later as an env override and still wins.
// #R001: Traceability for function `resolve_password`.
std::string resolve_password(const std::string& item) {
    try {
        const std::string password = onepsa::read_password_strict(item);
        if (!password.empty()) return password;
    } catch (const std::exception&) {
        // Fall through to ~/.env.
    }
    const auto env_fields = read_env_file_fields(item);
    auto it = env_fields.find("password");
    return it == env_fields.end() ? std::string() : it->second;
}

// #R001: Traceability for function `load_profile_document`.
json load_profile_document() {
    for (const auto& path : candidate_profile_paths()) {
        std::error_code ec;
        if (!fs::is_regular_file(path, ec)) continue;
        std::ifstream in(path);
        if (!in.is_open()) continue;
        json payload;
        try {
            in >> payload;
        } catch (const json::exception& exc) {
            throw ProfileError("Could not read DB profile file " + path.string() + ": " + exc.what());
        }
        if (!payload.is_object() || !payload.contains("profiles") || !payload["profiles"].is_object() ||
            payload["profiles"].empty()) {
            throw ProfileError("DB profile file " + path.string() +
                               " is missing a non-empty 'profiles' object");
        }
        return payload;
    }
    throw ProfileError(
        "No DB profile file found. Create one with: cp config/db-profiles-EXAMPLE.json config/db-profiles.json");
}

// #R001: Traceability for function `select_profile_name`.
std::string select_profile_name(const json& document) {
    const std::string override_name = trimmed(env_or_empty("TELLER_DB_PROFILE"));
    if (!override_name.empty()) return override_name;
    if (document.contains("default_profile") && document["default_profile"].is_string()) {
        const std::string name = trimmed(document["default_profile"].get<std::string>());
        if (!name.empty()) return name;
    }
    throw ProfileError("DB profile file is missing a non-empty 'default_profile'.");
}

// #R001: Traceability for function `resolve_item_name`.
std::string resolve_item_name(const json& document, const std::string& name) {
    const auto& profiles = document["profiles"];
    if (!profiles.contains(name) || !profiles[name].is_object()) {
        throw ProfileError("DB profile '" + name + "' not found");
    }
    const auto& record = profiles[name];
    for (const char* key : {"1psa_or_env_item", "1psa_item"}) {
        if (record.contains(key) && record[key].is_string()) {
            const std::string item = trimmed(record[key].get<std::string>());
            if (!item.empty()) return item;
        }
    }
    throw ProfileError("DB profile '" + name + "' is missing '1psa_or_env_item'");
}

// #R001: Traceability for function `default_sqlite_path`.
std::string default_sqlite_path() {
    return (fs::current_path() / ".database" / "teller.sqlite3").string();
}

// #R001: Traceability for function `parse_port`.
int parse_port(const std::string& raw, int fallback) {
    if (raw.empty()) return fallback;
    try {
        return std::stoi(raw);
    } catch (...) {
        return fallback;
    }
}

// #R001: Traceability for function `validate_sslmode`.
std::string validate_sslmode(const std::string& candidate, const std::string& source) {
    if (kAllowedSslmodes.count(candidate) > 0) return candidate;
    std::string allowed;
    for (const auto& mode : kAllowedSslmodes) {
        if (!allowed.empty()) allowed += ", ";
        allowed += mode;
    }
    throw ProfileError(source + " must be one of " + allowed + "; got '" + candidate + "'");
}

// teller_db_profile.py defaults: managed (Supabase) requires TLS unless the
// item says otherwise; local Postgres defaults to plaintext.
// #R001: Traceability for function `default_sslmode`.
std::string default_sslmode(DbTarget target) {
    return target == DbTarget::kManaged ? "require" : "disable";
}

// #R001: Traceability for function `target_from_field`.
DbTarget target_from_field(const std::string& value) {
    if (value == "managed") return DbTarget::kManaged;
    if (value == "sqlite") return DbTarget::kSqlite;
    return DbTarget::kLocal; // teller_db_profile.py: unknown targets resolve to local
}

// #R001: Traceability for function `apply_postgres_env_overrides`.
void apply_postgres_env_overrides(DbProfile& profile) {
    if (const std::string v = env_or_empty("TELLER_DB_HOST"); !v.empty()) profile.host = v;
    if (const std::string v = env_or_empty("TELLER_DB_PORT"); !v.empty()) {
        try {
            profile.port = std::stoi(v);
        } catch (...) {
            throw ProfileError("TELLER_DB_PORT must be an integer; got '" + v + "'");
        }
    }
    if (const std::string v = env_or_empty("TELLER_DB_NAME"); !v.empty()) profile.dbname = v;
    if (const std::string v = env_or_empty("TELLER_DB_USER"); !v.empty()) profile.user = v;
    if (std::getenv("TELLER_DB_ROLE") != nullptr) {
        profile.runtime_role = trimmed(env_or_empty("TELLER_DB_ROLE"));
    }
    if (const std::string v = trimmed(env_or_empty("TELLER_DB_SSLMODE")); !v.empty()) {
        profile.sslmode = validate_sslmode(v, "TELLER_DB_SSLMODE");
    }
    if (const std::string v = env_or_empty("TELLER_DB_SEARCH_PATH"); !v.empty()) {
        profile.search_path = v;
    }
    if (const std::string v = env_or_empty("TELLER_DB_PASSWORD"); !v.empty()) profile.password = v;
}

} // namespace

// #R001: Traceability for function `resolve_profile`.
DbProfile resolve_profile() {
    DbProfile profile;

    // Env overrides win outright (matching _apply_env_overrides): an explicit
    // sqlite path forces the sqlite target.
    const std::string env_path = trimmed(env_or_empty("TELLER_DB_SQLITE_PATH"));
    const std::string env_key = trimmed(env_or_empty("TELLER_DB_SQLCIPHER_KEY"));
    if (!env_path.empty()) {
        profile.name = "sqlite";
        profile.target = DbTarget::kSqlite;
        profile.sqlite_path = env_path;
        profile.sqlcipher_key = env_key;
        if (!profile.sqlcipher_key.empty()) return profile;
    }

    std::string item;
    try {
        const json document = load_profile_document();
        profile.name = select_profile_name(document);
        item = resolve_item_name(document, profile.name);
    } catch (const ProfileError&) {
        if (!env_path.empty() && !env_key.empty()) return profile;
        throw;
    }

    // Connection fields resolve through 1psa (libonepsa via dlopen) first, then
    // ~/.env as the documented fallback, mirroring teller_db_profile.py.
    const auto fields = resolve_item_fields(item);
    auto field = [&](const char* name) -> std::string {
        auto it = fields.find(name);
        return it == fields.end() ? std::string() : it->second;
    };

    // Mirroring teller_db_profile.py: a profile named "sqlite" forces the
    // sqlite target even when item metadata is missing/stale; otherwise the
    // item's target field decides (unknown/missing -> local Postgres).
    const bool item_targets_sqlite = field("target") == "sqlite";
    const bool is_sqlite = !env_path.empty() || profile.name == "sqlite" || item_targets_sqlite;

    if (is_sqlite) {
        profile.target = DbTarget::kSqlite;
        // The SQLCipher file path and key are per-machine secrets that
        // teller_db_profile.py reads straight from ~/.env (not 1psa) for the
        // sqlite profile, so an explicit env value beats the resolved record.
        const auto env_fields = read_env_file_fields(item);
        auto env_field = [&](const char* name) -> std::string {
            auto it = env_fields.find(name);
            return it == env_fields.end() ? std::string() : it->second;
        };
        if (profile.sqlite_path.empty()) {
            profile.sqlite_path = !env_field("sqlite_path").empty() ? env_field("sqlite_path")
                                                                    : field("sqlite_path");
            // "database" doubles as the path only when the item itself is a sqlite
            // target; on a forced name=="sqlite" profile with stale postgres-style
            // fields it would be a dbname like "prod", not a path (Python parity).
            if (profile.sqlite_path.empty() && item_targets_sqlite) {
                profile.sqlite_path = field("database");
            }
            if (profile.sqlite_path.empty()) profile.sqlite_path = default_sqlite_path();
        }
        if (profile.sqlcipher_key.empty()) {
            profile.sqlcipher_key = !env_key.empty()                    ? env_key
                                    : !field("sqlcipher_key").empty()   ? field("sqlcipher_key")
                                    : !env_field("sqlcipher_key").empty() ? env_field("sqlcipher_key")
                                                                          : env_field("password");
        }
        if (profile.sqlcipher_key.empty()) {
            throw ProfileError("DB profile '" + profile.name +
                               "' is missing sqlcipher_key. Set TELLER_DB_SQLCIPHER_KEY or add " +
                               item + ".sqlcipher_key=... to ~/.env");
        }
        return profile;
    }

    // Postgres targets: local Postgres or Supabase-managed Postgres, reached
    // over the wire protocol exactly like the retired psycopg2 path.
    profile.target = target_from_field(field("target"));
    profile.host = !field("host").empty() ? field("host") : "localhost";
    profile.port = parse_port(field("port"), 5432);
    profile.dbname = !field("database").empty() ? field("database") : "prod";
    profile.user = !field("username").empty() ? field("username") : "teller";
    profile.search_path = !field("schema").empty() ? field("schema") : "teller,classy,matchy";
    profile.runtime_role = field("runtime_role");
    // Password is not a connection field: resolve it via 1psa strict lookup
    // then ~/.env, mirroring teller_db._read_password. A field("password") from
    // the ~/.env-sourced record (resolve_item_fields fallback) still wins first.
    profile.password = !field("password").empty() ? field("password") : resolve_password(item);
    const std::string item_sslmode = trimmed(field("sslmode"));
    profile.sslmode = item_sslmode.empty() ? default_sslmode(profile.target)
                                           : validate_sslmode(item_sslmode, "DB profile sslmode");
    apply_postgres_env_overrides(profile);
    return profile;
}

// #R001: Traceability for function `resolve_sqlite_profile`.
SqliteProfile resolve_sqlite_profile() {
    const DbProfile profile = resolve_profile();
    if (profile.target != DbTarget::kSqlite) {
        throw ProfileError(
            "DB profile '" + profile.name + "' does not target sqlite. Select the sqlite profile "
            "(TELLER_DB_PROFILE=sqlite) or set TELLER_DB_SQLITE_PATH/TELLER_DB_SQLCIPHER_KEY "
            "explicitly.");
    }
    return SqliteProfile{profile.name, profile.sqlite_path, profile.sqlcipher_key};
}

} // namespace tellercore
// NOLINTEND(bugprone-throwing-static-initialization,cert-err58-cpp,concurrency-mt-unsafe,bugprone-empty-catch)
