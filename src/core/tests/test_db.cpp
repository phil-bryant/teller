#include <catch2/catch_test_macros.hpp>

#include "fixture.hpp"
#include "tellercore/db.hpp"

#ifdef TELLERCORE_ENABLE_POSTGRES
#include "tellercore/db_postgres.hpp"
#endif

using namespace tellercore;

TEST_CASE("SqliteDb bootstraps the teller schema and round-trips rows", "[db]") {
    testfx::Fixture fx(/*force_sqlite=*/true);
    fx.db->execute(
        "INSERT INTO teller.institution (institution_id, name) VALUES (:id, :name)",
        {{"id", std::string("ins_x")}, {"name", std::string("Test Bank")}});
    auto row = fx.db->query_one(
        "SELECT name FROM teller.institution WHERE institution_id = :id",
        {{"id", std::string("ins_x")}});
    REQUIRE(row.has_value());
    CHECK(row->get_text("name") == "Test Bank");
}

TEST_CASE("transaction rollback discards writes", "[db]") {
    testfx::Fixture fx(/*force_sqlite=*/true);
    fx.db->begin();
    fx.db->execute(
        "INSERT INTO teller.institution (institution_id, name) VALUES ('ins_rb', 'Rollback Bank')");
    fx.db->rollback();
    auto row = fx.db->query_one(
        "SELECT COUNT(*) AS n FROM teller.institution WHERE institution_id = 'ins_rb'");
    CHECK(row->get_int("n").value_or(-1) == 0);
}

#ifdef TELLERCORE_ENABLE_POSTGRES
TEST_CASE("translate_named_params rewrites :name to positional placeholders", "[db][pg]") {
    const auto t = db::translate_named_params(
        "SELECT * FROM t WHERE a = :a AND b = :b AND c = :a AND d = 'literal :a'");
    CHECK(t.sql == "SELECT * FROM t WHERE a = $1 AND b = $2 AND c = $1 AND d = 'literal :a'");
    REQUIRE(t.param_names.size() == 2);
    CHECK(t.param_names[0] == "a");
    CHECK(t.param_names[1] == "b");
}
#endif
