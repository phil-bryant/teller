#include <catch2/catch_test_macros.hpp>

#include <string>
#include <vector>

#include "tellercore/ocr.hpp"
#include "tellercore/statement.hpp"

using namespace tellercore;
using statement::StatementTxn;

namespace {

ocr::Observation obs(double y, double x, const std::string& text) { return {y, x, text}; }

} // namespace

TEST_CASE("reconstruct_lines clusters by y and orders chunks by x", "[statement]") {
    const ocr::Page page = {obs(0.90, 0.50, "World"), obs(0.90, 0.10, "Hello"),
                            obs(0.50, 0.20, "Second")};
    const std::vector<std::string> lines = statement::reconstruct_lines(page);
    REQUIRE(lines.size() == 2);
    CHECK(lines[0] == "Hello World");
    CHECK(lines[1] == "Second");
}

TEST_CASE("parse_transactions infers signed amounts and types", "[statement]") {
    const std::vector<std::string> pages = {
        "Date Activity Description Amount\n"
        "05/03 POS PURCHASE WHOLE FOODS 45.67\n"
        "05/05 DEPOSIT PAYROLL 1,200.00\n"
        "05/31 INTEREST EARNED 0.12"};
    const std::vector<StatementTxn> txns = statement::parse_transactions(pages, 2026, 5);
    REQUIRE(txns.size() == 3);

    CHECK(txns[0].date == "2026-05-03");
    CHECK(txns[0].amount == "-45.67");
    CHECK(txns[0].description == "POS PURCHASE WHOLE FOODS");
    CHECK(txns[0].type == "card_payment");

    CHECK(txns[1].date == "2026-05-05");
    CHECK(txns[1].amount == "1200.00");
    CHECK(txns[1].description == "DEPOSIT PAYROLL");
    CHECK(txns[1].type == "deposit");

    CHECK(txns[2].date == "2026-05-31");
    CHECK(txns[2].amount == "0.12");
    CHECK(txns[2].type == "interest");
}

TEST_CASE("parse_transactions normalizes bare-cent amounts", "[statement]") {
    const std::vector<std::string> pages = {
        "Date Activity Description Amount\n"
        "07/04 ATM WITHDRAWAL .50"};
    const std::vector<StatementTxn> txns = statement::parse_transactions(pages, 2026, 7);
    REQUIRE(txns.size() == 1);
    CHECK(txns[0].amount == "-0.50");
    CHECK(txns[0].type == "atm");
}

TEST_CASE("parse_transactions merges split date lines", "[statement]") {
    const std::vector<std::string> pages = {
        "Date Activity Description Amount\n"
        "08/09\n"
        "BILL PAY ELECTRIC 88.00"};
    const std::vector<StatementTxn> txns = statement::parse_transactions(pages, 2026, 8);
    REQUIRE(txns.size() == 1);
    CHECK(txns[0].date == "2026-08-09");
    CHECK(txns[0].amount == "-88.00");
    CHECK(txns[0].type == "ach");
}

TEST_CASE("parse_transactions rescues buried interest", "[statement]") {
    const std::vector<std::string> pages = {
        "Date Activity Description Amount\n"
        "06/15 ACCT ANALYSIS INTEREST EARNED 1.23"};
    const std::vector<StatementTxn> txns = statement::parse_transactions(pages, 2026, 6);
    REQUIRE(txns.size() == 2);
    // The rescued row is appended and dated the last day of the statement month.
    CHECK(txns[1].description == "INTEREST EARNED");
    CHECK(txns[1].amount == "1.23");
    CHECK(txns[1].type == "interest");
    CHECK(txns[1].date == "2026-06-30");
}

TEST_CASE("extract_statement_year reads the statement date marker", "[statement]") {
    const std::vector<std::string> pages = {"Some header\nStatement Date 05/31/26\nmore"};
    const statement::StatementYear period = statement::extract_statement_year(pages);
    CHECK(period.year == 2026);
    CHECK(period.month == 5);
}

TEST_CASE("extract_summary scrapes control totals", "[statement]") {
    const std::vector<std::string> pages = {
        "Deposits / Misc Credits 3 1,200.12\n"
        "Withdrawals / Misc Debits 1 45.67"};
    const statement::SummaryTotals totals = statement::extract_summary(pages);
    REQUIRE(totals.deposit_count.has_value());
    CHECK(*totals.deposit_count == 3);
    CHECK(*totals.deposit_total == "1200.12");
    REQUIRE(totals.withdrawal_count.has_value());
    CHECK(*totals.withdrawal_count == 1);
    CHECK(*totals.withdrawal_total == "45.67");
}

TEST_CASE("extract_last_four_hint prefers the filename", "[statement]") {
    const std::vector<std::string> pages = {"Account #: ****9999"};
    const auto hint = statement::extract_last_four_hint("EStatement_6414_D_2026.pdf", pages);
    REQUIRE(hint.has_value());
    CHECK(*hint == "6414");
}

TEST_CASE("extract_last_four_hint falls back to OCR head", "[statement]") {
    const auto stars = statement::extract_last_four_hint("statement.pdf", {"balance ****1234 here"});
    REQUIRE(stars.has_value());
    CHECK(*stars == "1234");

    const auto account = statement::extract_last_four_hint("statement.pdf", {"Account # 5678"});
    REQUIRE(account.has_value());
    CHECK(*account == "5678");

    const auto ending = statement::extract_last_four_hint("statement.pdf", {"ending in 4321"});
    REQUIRE(ending.has_value());
    CHECK(*ending == "4321");

    CHECK_FALSE(statement::extract_last_four_hint("statement.pdf", {"no hint here"}).has_value());
}

TEST_CASE("make_txn_id is deterministic and occurrence-sensitive", "[statement]") {
    const std::string a =
        statement::make_txn_id("acc_1", "2026-05-03", "-45.67", "WHOLE FOODS", 1);
    const std::string b =
        statement::make_txn_id("acc_1", "2026-05-03", "-45.67", "WHOLE FOODS", 1);
    const std::string c =
        statement::make_txn_id("acc_1", "2026-05-03", "-45.67", "WHOLE FOODS", 2);
    CHECK(a == b);
    CHECK(a != c);
    CHECK(a.rfind("stmt_", 0) == 0);
    CHECK(a.size() == 25);  // "stmt_" + 20 hex chars
}
