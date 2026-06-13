#pragma once

#include <filesystem>
#include <memory>
#include <string>

#include "tellercore/db.hpp"

namespace tellercore::testfx {

// Bootstraps an empty teller schema for persist/ingest tests.
//
// Backend selection: a temp SQLCipher file by default. When
// TELLER_TEST_PG_CONNINFO is set (and the build has libpq), the fixture
// connects to that live Postgres database and truncates the teller-owned
// tables so the same persist suites prove both dialects. Pass force_sqlite=true
// for SQLite-specific tests (SQLCipher key handling).
struct Fixture {
    explicit Fixture(bool force_sqlite = false);
    ~Fixture();

    std::filesystem::path dir;
    std::string db_path;
    std::string key = "teller-test-key";
    std::unique_ptr<db::Db> db;

    bool postgres() const { return !pg_conninfo.empty(); }
    void reopen();

private:
    std::string pg_conninfo;
};

} // namespace tellercore::testfx
