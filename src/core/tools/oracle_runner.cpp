// Oracle harness CLI for the persist parity lane (t17).
//
// The parity unit for teller is ingestion: applying a Teller API payload through
// teller_persist (Python) and tellercore::persist (C++) must leave identical
// teller.* state. This runner drives the C++ side.
//
// Single-op (debugging):
//   teller_oracle_runner --db <path> --key <key> persist <payload-json>
//   teller_oracle_runner --db <path> --key <key> snapshot
//   teller_oracle_runner --db <path> --key <key> bootstrap <ddl-file>
//
// Replay (lane t17): for each scenario, bootstrap a fresh fixture from the
// SQLite DDL, apply every step's persist payload, snapshot the normalized
// teller.* state, and either record it or diff against committed goldens.
//
//   teller_oracle_runner replay --scenarios <json> --ddl <sql> \
//       (--record <json> | --golden <json>) [--key <key>]
//
// A "step" payload is {identities, transactions_by_account, balances_by_account}.

#include <unistd.h>

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <regex>
#include <sstream>
#include <tuple>
#include <utility>
#include <vector>

#include "tellercore/db.hpp"
#ifdef TELLERCORE_ENABLE_POSTGRES
#include "tellercore/db_postgres.hpp"
#endif
#include "tellercore/error.hpp"
#include "tellercore/json_io.hpp"
#include "tellercore/ocr.hpp"
#include "tellercore/persist.hpp"
#include "tellercore/statement.hpp"

using namespace tellercore;
using nlohmann::json;

namespace {

// (table, order-by column). Snapshot order mirrors the persist write order so
// AUTOINCREMENT ids line up between the Python and C++ runs.
const std::vector<std::pair<std::string, std::string>> kSnapshotTables = {
    {"institution", "institution_id"},
    {"account_links", "account_links_id"},
    {"account", "account_id"},
    {"identity", "identity_id"},
    {"identity_name", "identity_name_id"},
    {"identity_email", "identity_email_id"},
    {"identity_phone_number", "identity_phone_number_id"},
    {"identity_address_data", "identity_address_data_id"},
    {"identity_address", "identity_address_id"},
    {"account_identities", "account_identities_id"},
    {"account_balances_links", "account_balances_links_id"},
    {"account_balances", "account_balances_id"},
    {"transaction_type", "transaction_type_id"},
    {"transaction_details_counterparty", "transaction_details_counterparty_id"},
    {"transaction_details", "transaction_details_id"},
    {"transaction_links", "transaction_links_id"},
    {"transaction", "transaction_id"},
};

std::string quoted_table(const std::string& table) {
    return table == "transaction" ? "teller.\"transaction\"" : "teller." + table;
}

// Drop bookkeeping timestamps that legitimately differ run-to-run; everything
// else (ids, money, text, FKs) must match across backends and languages.
json normalize_row(const db::Row& row) {
    json out = json::object();
    for (const auto& [name, value] : row.columns) {
        if (name == "created_at" || name == "updated_at") continue;
        out[name] = json_io::value_to_json(value);
    }
    return out;
}

json snapshot(db::Db& db) {
    json out = json::object();
    for (const auto& [table, order_by] : kSnapshotTables) {
        json rows = json::array();
        for (const auto& row : db.query("SELECT * FROM " + quoted_table(table) + " ORDER BY " + order_by)) {
            rows.push_back(normalize_row(row));
        }
        out[table] = std::move(rows);
    }
    return out;
}

void apply_step(db::Db& db, const json& step) {
    const json identities = step.contains("identities") ? step["identities"] : json::array();
    const json txns = step.contains("transactions_by_account") ? step["transactions_by_account"]
                                                                : json::object();
    const json balances = step.contains("balances_by_account") ? step["balances_by_account"]
                                                                : json::object();
    persist::persist_all(db, identities, txns, balances);
}

std::string read_file(const std::string& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot read " + path);
    std::stringstream buffer;
    buffer << in.rdbuf();
    return buffer.str();
}

json load_json_file(const std::string& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot read " + path);
    return json::parse(in);
}

int run_replay(int argc, char** argv) {
    std::string scenarios_path, ddl_path, record_path, golden_path, pg_conninfo;
    std::string key = "teller-oracle-key";
    for (int i = 2; i < argc; ++i) {
        const std::string arg = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 >= argc) throw std::runtime_error("missing value for " + arg);
            return argv[++i];
        };
        if (arg == "--scenarios") scenarios_path = next();
        else if (arg == "--ddl") ddl_path = next();
        else if (arg == "--record") record_path = next();
        else if (arg == "--golden") golden_path = next();
        else if (arg == "--key") key = next();
        else if (arg == "--pg") pg_conninfo = next();
        else throw std::runtime_error("unknown replay argument: " + arg);
    }
    if (scenarios_path.empty() || (ddl_path.empty() && pg_conninfo.empty()) ||
        (record_path.empty() == golden_path.empty())) {
        std::cerr << "usage: teller_oracle_runner replay --scenarios <json> "
                     "(--ddl <sql> | --pg <conninfo>) (--record <json> | --golden <json>) [--key <key>]\n";
        return 2;
    }

    const json script = load_json_file(scenarios_path);
    const json* golden = nullptr;
    json golden_doc;
    if (!golden_path.empty()) {
        golden_doc = load_json_file(golden_path);
        golden = &golden_doc.at("scenarios");
    }

    json recorded = json::array();
    int failures = 0;
    size_t scenario_index = 0;
    for (const auto& scenario : script.at("scenarios")) {
        const std::string name = scenario.at("name").get<std::string>();
        std::unique_ptr<db::Db> backend;
        std::string tmpdir;
        if (!pg_conninfo.empty()) {
#ifdef TELLERCORE_ENABLE_POSTGRES
            auto pg = std::make_unique<db::PostgresDb>(pg_conninfo);
            pg->execute_script(
                "TRUNCATE teller.\"transaction\", teller.transaction_links, "
                "teller.transaction_details, teller.transaction_details_counterparty, "
                "teller.transaction_type, teller.account_balances, teller.account_balances_links, "
                "teller.account_identities, teller.identity_address, teller.identity_address_data, "
                "teller.identity_phone_number, teller.identity_email, teller.identity_name, "
                "teller.identity, teller.account, teller.account_links, teller.institution "
                "RESTART IDENTITY CASCADE");
            backend = std::move(pg);
#else
            throw std::runtime_error("--pg requires a build with TELLERCORE_ENABLE_POSTGRES=ON");
#endif
        } else {
            char tmpl[] = "/tmp/teller-oracle-XXXXXX";
            const char* dir = mkdtemp(tmpl);
            if (!dir) throw std::runtime_error("mkdtemp failed");
            tmpdir = dir;
            const std::string db_path = tmpdir + "/fixture.sqlite3";
            db::SqliteDb::bootstrap_file(db_path, key, read_file(ddl_path));
            backend = std::make_unique<db::SqliteDb>(db_path, key);
        }

        for (const auto& step : scenario.at("steps")) apply_step(*backend, step);
        const json snap = snapshot(*backend);
        backend.reset();
        if (!tmpdir.empty()) std::filesystem::remove_all(tmpdir);

        if (golden) {
            const json* expected = nullptr;
            if (scenario_index < golden->size() && (*golden)[scenario_index].at("name") == name) {
                expected = &(*golden)[scenario_index].at("snapshot");
            }
            if (!expected || *expected != snap) {
                ++failures;
                std::cout << "GOLDEN FAIL: " << name << "\n";
            }
        }
        recorded.push_back(json{{"name", name}, {"snapshot", snap}});
        ++scenario_index;
    }

    if (!record_path.empty()) {
        std::ofstream out(record_path);
        if (!out) throw std::runtime_error("cannot write " + record_path);
        out << json{{"scenarios", recorded}}.dump(2) << "\n";
        std::cout << "recorded " << recorded.size() << " scenarios to " << record_path << "\n";
    } else {
        std::cout << "oracle golden replay: " << recorded.size() << " scenarios, " << failures
                  << " failures\n";
    }
    return failures ? 1 : 0;
}

// Statement parsing parity lane (t19): drive the tellercore::statement parser
// from canned OCR observation fixtures and emit the parsed transactions (with
// deterministic ids), period, and summary totals as JSON on stdout. The Python
// harness runs the retired 08_backfill_bank_statements functions on the same
// fixtures and diffs the two, holding the C++ parser to the Python oracle while
// keeping the drift-prone logic out of nondeterministic OCR.
//
//   teller_oracle_runner replay-statements --scenarios <json>
int run_statement_replay(int argc, char** argv) {
    std::string scenarios_path;
    for (int i = 2; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--scenarios" && i + 1 < argc) scenarios_path = argv[++i];
        else throw std::runtime_error("unknown replay-statements argument: " + arg);
    }
    if (scenarios_path.empty()) {
        std::cerr << "usage: teller_oracle_runner replay-statements --scenarios <json>\n";
        return 2;
    }

    const json script = load_json_file(scenarios_path);
    json recorded = json::array();
    for (const auto& scenario : script.at("scenarios")) {
        const std::string name = scenario.at("name").get<std::string>();
        const std::string account_id = scenario.value("account_id", "acc_test");

        std::vector<ocr::Page> pages;
        for (const auto& page_json : scenario.at("pages")) {
            ocr::Page page;
            for (const auto& o : page_json.at("observations")) {
                page.push_back({o.at("y").get<double>(), o.at("x").get<double>(),
                                o.at("text").get<std::string>()});
            }
            pages.push_back(std::move(page));
        }
        const std::vector<std::string> page_texts = statement::pages_to_text(pages);

        int year = 0;
        int month = 0;
        if (scenario.contains("year") && scenario.contains("month")) {
            year = scenario.at("year").get<int>();
            month = scenario.at("month").get<int>();
        } else {
            const statement::StatementYear period = statement::extract_statement_year(page_texts);
            year = period.year;
            month = period.month;
        }

        const std::vector<statement::StatementTxn> txns =
            statement::parse_transactions(page_texts, year, month);
        std::map<std::tuple<std::string, std::string, std::string>, int> seen;
        json txn_arr = json::array();
        for (const auto& t : txns) {
            const int occurrence = ++seen[std::make_tuple(t.date, t.amount, t.description)];
            txn_arr.push_back(json{
                {"id", statement::make_txn_id(account_id, t.date, t.amount, t.description, occurrence)},
                {"date", t.date},
                {"amount", t.amount},
                {"description", t.description},
                {"type", t.type}});
        }

        const statement::SummaryTotals summary = statement::extract_summary(page_texts);
        json summary_json = {
            {"deposit_count", summary.deposit_count ? json(*summary.deposit_count) : json(nullptr)},
            {"deposit_total", summary.deposit_total ? json(*summary.deposit_total) : json(nullptr)},
            {"withdrawal_count",
             summary.withdrawal_count ? json(*summary.withdrawal_count) : json(nullptr)},
            {"withdrawal_total",
             summary.withdrawal_total ? json(*summary.withdrawal_total) : json(nullptr)}};

        recorded.push_back(json{{"name", name},
                                {"year", year},
                                {"month", month},
                                {"transactions", txn_arr},
                                {"summary", summary_json}});
    }
    std::cout << json{{"scenarios", recorded}}.dump() << "\n";
    return 0;
}

int run(int argc, char** argv) {
    if (argc > 1 && std::string(argv[1]) == "replay") return run_replay(argc, argv);
    if (argc > 1 && std::string(argv[1]) == "replay-statements")
        return run_statement_replay(argc, argv);
    std::string db_path, key, op;
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--db" && i + 1 < argc) db_path = argv[++i];
        else if (arg == "--key" && i + 1 < argc) key = argv[++i];
        else if (op.empty()) op = arg;
        else args.push_back(arg);
    }
    if (key.empty()) {
        if (const char* env_key = std::getenv("TELLER_DB_SQLCIPHER_KEY")) key = env_key;
    }
    if (db_path.empty() || op.empty()) {
        std::cerr << "usage: teller_oracle_runner --db <path> --key <key> <persist|snapshot|bootstrap> [arg]\n";
        return 2;
    }
    if (op == "bootstrap") {
        db::SqliteDb::bootstrap_file(db_path, key, read_file(args.at(0)));
        std::cout << json{{"ok", true}}.dump() << "\n";
        return 0;
    }
    db::SqliteDb database(db_path, key);
    if (op == "persist") {
        apply_step(database, json::parse(args.at(0)));
        std::cout << json{{"ok", true}}.dump() << "\n";
        return 0;
    }
    if (op == "snapshot") {
        std::cout << snapshot(database).dump() << "\n";
        return 0;
    }
    throw std::runtime_error("unknown op: " + op);
}

} // namespace

int main(int argc, char** argv) {
    try {
        return run(argc, argv);
    } catch (const ApiError& exc) {
        std::cout << json{{"error", {{"status", exc.status()}, {"detail", exc.detail()}}}}.dump()
                  << "\n";
        return 1;
    } catch (const std::exception& exc) {
        std::cout << json{{"error", {{"status", 500}, {"detail", exc.what()}}}}.dump() << "\n";
        return 1;
    }
}
