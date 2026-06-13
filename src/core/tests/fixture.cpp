#include "fixture.hpp"

#include <cstdlib>
#include <fstream>
#include <random>
#include <sstream>
#include <stdexcept>

#ifdef TELLERCORE_ENABLE_POSTGRES
#include "tellercore/db_postgres.hpp"
#endif

namespace tellercore::testfx {

namespace {

std::string read_file(const std::string& path) {
    std::ifstream in(path);
    if (!in.is_open()) throw std::runtime_error("cannot open DDL: " + path);
    std::stringstream buffer;
    buffer << in.rdbuf();
    return buffer.str();
}

std::filesystem::path make_temp_dir() {
    std::random_device rd;
    auto dir = std::filesystem::temp_directory_path() / ("tellercore-test-" + std::to_string(rd()));
    std::filesystem::create_directories(dir);
    return dir;
}

#ifdef TELLERCORE_ENABLE_POSTGRES
// Returns a live-Postgres database to a pristine empty ingest state.
const char* kPostgresReset = R"SQL(
TRUNCATE teller."transaction",
         teller.transaction_links,
         teller.transaction_details,
         teller.transaction_details_counterparty,
         teller.transaction_type,
         teller.account_balances,
         teller.account_balances_links,
         teller.account_identities,
         teller.identity_address,
         teller.identity_address_data,
         teller.identity_phone_number,
         teller.identity_email,
         teller.identity_name,
         teller.identity,
         teller.account,
         teller.account_links,
         teller.institution
RESTART IDENTITY CASCADE;
)SQL";
#endif

} // namespace

Fixture::Fixture(bool force_sqlite) {
#ifdef TELLERCORE_ENABLE_POSTGRES
    if (!force_sqlite) {
        const char* conninfo = std::getenv("TELLER_TEST_PG_CONNINFO");
        if (conninfo != nullptr && conninfo[0] != '\0') pg_conninfo = conninfo;
    }
#else
    (void)force_sqlite;
#endif
    if (postgres()) {
#ifdef TELLERCORE_ENABLE_POSTGRES
        auto pg = std::make_unique<db::PostgresDb>(pg_conninfo);
        pg->execute_script(kPostgresReset);
        db = std::move(pg);
#endif
    } else {
        dir = make_temp_dir();
        db_path = (dir / "teller.sqlite3").string();
        db::SqliteDb::bootstrap_file(db_path, key, read_file(TELLER_SQLITE_DDL_PATH));
        db = std::make_unique<db::SqliteDb>(db_path, key);
    }
}

Fixture::~Fixture() {
    db.reset();
    if (!dir.empty()) {
        std::error_code ec;
        std::filesystem::remove_all(dir, ec);
    }
}

void Fixture::reopen() {
    if (postgres()) {
#ifdef TELLERCORE_ENABLE_POSTGRES
        db = std::make_unique<db::PostgresDb>(pg_conninfo);
#endif
        return;
    }
    db = std::make_unique<db::SqliteDb>(db_path, key);
}

} // namespace tellercore::testfx
