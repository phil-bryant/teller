#include <catch2/catch_test_macros.hpp>

#include <nlohmann/json.hpp>

#include "fixture.hpp"
#include "tellercore/persist.hpp"

using namespace tellercore;
using nlohmann::json;

namespace {

json make_account(const std::string& account_id = "acc_1") {
    return json{
        {"id", account_id},
        {"currency", "USD"},
        {"enrollment_id", "enr_1"},
        {"last_four", "4242"},
        {"name", "Checking"},
        {"type", "depository"},
        {"subtype", "checking"},
        {"status", "open"},
        {"institution", {{"id", "ins_1"}, {"name", "Test Bank"}}},
        {"links",
         {{"self", "https://example/" + account_id},
          {"details", "https://example/" + account_id + "/details"},
          {"balances", "https://example/" + account_id + "/balances"},
          {"transactions", "https://example/" + account_id + "/transactions"}}}};
}

json make_owner() {
    return json{{"type", "person"},
                {"names", json::array({{{"type", "name"}, {"data", "Jane Doe"}}})},
                {"emails", json::array({{{"data", "jane@example.com"}}})},
                {"phone_numbers", json::array()},
                {"addresses", json::array()}};
}

json make_txn(const std::string& id, const std::string& amount, const std::string& status) {
    return json{{"id", id},
                {"account_id", "acc_1"},
                {"amount", amount},
                {"date", "2026-06-01"},
                {"description", "WHOLE FOODS"},
                {"status", status},
                {"type", "card_payment"},
                {"running_balance", "100.00"},
                {"details",
                 {{"processing_status", "complete"},
                  {"category", "groceries"},
                  {"counterparty", {{"name", "STORE"}, {"type", "organization"}}}}},
                {"links", {{"self", "https://example/" + id}, {"account", "acc_1"}}}};
}

} // namespace

TEST_CASE("persist_all ingests an account, identity and transactions", "[persist][postgres]") {
    testfx::Fixture fx;
    json identities = json::array({{{"account", make_account()}, {"owners", json::array({make_owner()})}}});
    json txns;
    txns["acc_1"] = json::array({make_txn("txn_1", "12.34", "posted")});
    json balances;
    balances["acc_1"] = json{{"account_id", "acc_1"},
                             {"ledger", "1000.00"},
                             {"available", "950.00"},
                             {"links", {{"self", "https://example/acc_1/bal"},
                                        {"account", "https://example/acc_1"}}}};

    persist::persist_all(*fx.db, identities, txns, balances);

    auto acct = fx.db->query_one(
        "SELECT name, status FROM teller.account WHERE account_id = 'acc_1'");
    REQUIRE(acct.has_value());
    CHECK(acct->get_text("status") == "open");

    auto txn = fx.db->query_one(
        "SELECT amount, status FROM teller.\"transaction\" WHERE transaction_id = 'txn_1'");
    REQUIRE(txn.has_value());
    if (fx.db->dialect() == Dialect::kSqlite) {
        CHECK(txn->get_int("amount").value() == 1234);
    } else {
        CHECK(txn->get_double("amount").value() == 12.34);
    }

    auto email = fx.db->query_one(
        "SELECT data FROM teller.identity_email WHERE data = 'jane@example.com'");
    CHECK(email.has_value());
}

TEST_CASE("persist_all is idempotent across reruns", "[persist][postgres]") {
    testfx::Fixture fx;
    json identities = json::array({{{"account", make_account()}, {"owners", json::array({make_owner()})}}});
    json txns;
    txns["acc_1"] = json::array({make_txn("txn_1", "12.34", "posted")});

    persist::persist_all(*fx.db, identities, txns, json::object());
    persist::persist_all(*fx.db, identities, txns, json::object());

    auto count = fx.db->query_one("SELECT COUNT(*) AS n FROM teller.\"transaction\"");
    CHECK(count->get_int("n").value() == 1);
    auto inst = fx.db->query_one("SELECT COUNT(*) AS n FROM teller.institution");
    CHECK(inst->get_int("n").value() == 1);
}

TEST_CASE("posted transactions win over pending duplicates", "[persist][postgres]") {
    testfx::Fixture fx;
    json identities = json::array({{{"account", make_account()}, {"owners", json::array({make_owner()})}}});
    json txns;
    txns["acc_1"] = json::array(
        {make_txn("txn_dup", "5.00", "pending"), make_txn("txn_dup", "5.00", "posted")});

    persist::persist_all(*fx.db, identities, txns, json::object());

    auto row = fx.db->query_one(
        "SELECT status FROM teller.\"transaction\" WHERE transaction_id = 'txn_dup'");
    REQUIRE(row.has_value());
    CHECK(row->get_text("status") == "posted");
}

TEST_CASE("stale pending transactions are reconciled away", "[persist][postgres]") {
    testfx::Fixture fx;
    json identities = json::array({{{"account", make_account()}, {"owners", json::array({make_owner()})}}});

    json first;
    first["acc_1"] = json::array(
        {make_txn("txn_keep", "5.00", "posted"), make_txn("txn_pending", "9.00", "pending")});
    persist::persist_all(*fx.db, identities, first, json::object());

    json second;
    second["acc_1"] = json::array({make_txn("txn_keep", "5.00", "posted")});
    persist::persist_all(*fx.db, identities, second, json::object());

    auto pending = fx.db->query_one(
        "SELECT COUNT(*) AS n FROM teller.\"transaction\" WHERE transaction_id = 'txn_pending'");
    CHECK(pending->get_int("n").value() == 0);
    auto keep = fx.db->query_one(
        "SELECT COUNT(*) AS n FROM teller.\"transaction\" WHERE transaction_id = 'txn_keep'");
    CHECK(keep->get_int("n").value() == 1);
}
