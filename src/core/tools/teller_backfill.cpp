// teller_backfill: C++ port of 08_backfill_bank_statements.py.
//
// Discovers bank-statement PDFs under a per-institution statement root, OCRs
// them through the platform OcrBackend (Apple Vision / Windows OCR), parses the
// activity tables with the shared tellercore::statement parser, matches each
// statement to a teller account, and persists the backfilled transactions with
// deterministic ids -- skipping any date already covered by the live Teller API
// ingest. The retired Python script remains the parsing reference oracle.
//
//   teller_backfill [--institution-id <id>] [--account-id <id>]
//                   [--statements-root <dir>] [--dry-run] [--debug]
//
// Statement root resolution (mirrors the Python script):
//   --statements-root, else $TELLER_BANK_STATEMENTS_ROOT, else
//   ./config/bank_statements relative to the current directory.

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "tellercore/db.hpp"
#include "tellercore/error.hpp"
#include "tellercore/ocr.hpp"
#include "tellercore/persist.hpp"
#include "tellercore/profile.hpp"
#include "tellercore/statement.hpp"

using namespace tellercore;
namespace fs = std::filesystem;

namespace {

constexpr const char* kStatementsRootEnv = "TELLER_BANK_STATEMENTS_ROOT";

struct Args {
    std::optional<std::string> institution_id;
    std::optional<std::string> account_id;
    std::optional<std::string> statements_root;
    bool dry_run = false;
    bool debug = false;
};

struct AccountRow {
    std::string account_id;
    std::string name;
    std::optional<std::string> last_four;
};

bool parse_args(int argc, char** argv, Args& args) {
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        auto next = [&](const char* flag) -> std::string {
            if (i + 1 >= argc) throw ApiError(2, std::string("missing value for ") + flag);
            return argv[++i];
        };
        if (arg == "--institution-id") args.institution_id = next("--institution-id");
        else if (arg == "--account-id") args.account_id = next("--account-id");
        else if (arg == "--statements-root") args.statements_root = next("--statements-root");
        else if (arg == "--dry-run") args.dry_run = true;
        else if (arg == "--debug") args.debug = true;
        else return false;
    }
    if (args.account_id && !args.institution_id) {
        throw ApiError(2, "--account-id requires --institution-id");
    }
    return true;
}

fs::path statements_root(const std::optional<std::string>& cli_root) {
    std::string root;
    if (cli_root && !cli_root->empty()) {
        root = *cli_root;
    } else if (const char* env = std::getenv(kStatementsRootEnv)) {
        root = env;
    }
    // Trim surrounding whitespace, mirroring the Python .strip().
    const auto begin = root.find_first_not_of(" \t\r\n");
    const auto end = root.find_last_not_of(" \t\r\n");
    root = begin == std::string::npos ? "" : root.substr(begin, end - begin + 1);
    if (root.empty()) return fs::current_path() / "config" / "bank_statements";
    return fs::absolute(fs::path(root));
}

std::vector<std::string> list_institution_ids(db::Db& db, const std::optional<std::string>& only) {
    if (only) return {*only};
    std::vector<std::string> ids;
    for (const auto& row :
         db.query("SELECT DISTINCT institution_id FROM teller.account ORDER BY institution_id")) {
        if (auto id = row.get_text("institution_id")) ids.push_back(*id);
    }
    return ids;
}

std::vector<fs::path> pdfs_for_institution(const fs::path& root, const std::string& institution_id) {
    const fs::path dir = root / institution_id;
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) return {};
    std::vector<fs::path> pdfs;
    for (const auto& entry : fs::directory_iterator(dir, ec)) {
        if (entry.is_regular_file() && entry.path().extension() == ".pdf") {
            pdfs.push_back(entry.path());
        }
    }
    std::sort(pdfs.begin(), pdfs.end());
    return pdfs;
}

std::vector<AccountRow> accounts_for_institution(db::Db& db, const std::string& institution_id) {
    std::vector<AccountRow> rows;
    for (const auto& row : db.query(
             "SELECT account_id, name, last_four FROM teller.account "
             "WHERE institution_id = :iid ORDER BY name",
             {{"iid", institution_id}})) {
        AccountRow account;
        account.account_id = row.get_text("account_id").value_or("");
        account.name = row.get_text("name").value_or("");
        account.last_four = row.is_null("last_four") ? std::nullopt : row.get_text("last_four");
        rows.push_back(std::move(account));
    }
    if (rows.empty()) {
        throw ApiError(1, "No account rows for institution_id=" + institution_id);
    }
    return rows;
}

std::string match_statement_to_account(const fs::path& pdf_path,
                                        const std::vector<std::string>& pages,
                                        const std::vector<AccountRow>& account_rows,
                                        const std::optional<std::string>& account_id_override) {
    if (account_id_override) {
        for (const auto& row : account_rows) {
            if (row.account_id == *account_id_override) return row.account_id;
        }
        throw ApiError(1, "--account-id " + *account_id_override +
                              " is not an account for this institution");
    }
    if (account_rows.size() == 1) return account_rows.front().account_id;

    const std::optional<std::string> hint =
        statement::extract_last_four_hint(pdf_path.filename().string(), pages);
    if (!hint) {
        throw ApiError(1, "Multiple accounts at this institution but could not read last four from " +
                              pdf_path.filename().string() +
                              " (try a filename like EStatement_LAST4_... or fix OCR).");
    }
    std::vector<std::string> matches;
    for (const auto& row : account_rows) {
        if (row.last_four && *row.last_four == *hint) matches.push_back(row.account_id);
    }
    if (matches.size() == 1) {
        std::cout << "Matched statement to account: pdf=" << pdf_path.filename().string()
                  << " last_four=" << *hint << " account_id=" << matches.front() << "\n";
        return matches.front();
    }
    if (matches.empty()) {
        throw ApiError(1, "No teller.account with last_four=" + *hint + " for " +
                              pdf_path.filename().string() + "; check DB vs statement.");
    }
    throw ApiError(1, "Multiple accounts with last_four=" + *hint + " in DB (unexpected).");
}

// Sum the absolute cents of positive (deposits) or negative (withdrawals) txns.
int64_t sum_cents(const std::vector<statement::StatementTxn>& txns, bool positive) {
    int64_t total = 0;
    for (const auto& txn : txns) {
        const int64_t cents = persist::money_to_cents(txn.amount);
        if (positive && cents > 0) total += cents;
        if (!positive && cents < 0) total += -cents;
    }
    return total;
}

std::string cents_to_string(int64_t cents) {
    const bool negative = cents < 0;
    const int64_t abs_cents = negative ? -cents : cents;
    std::string out = (negative ? "-" : "") + std::to_string(abs_cents / 100) + "." +
                      (abs_cents % 100 < 10 ? "0" : "") + std::to_string(abs_cents % 100);
    return out;
}

struct ParsedStatement {
    std::string account_id;
    std::vector<statement::StatementTxn> txns;
};

ParsedStatement parse_statement_pdf(ocr::OcrBackend& backend, const fs::path& pdf_path,
                                    const std::string& institution_id,
                                    const std::vector<AccountRow>& account_rows,
                                    const std::optional<std::string>& account_id_override) {
    std::cout << "Processing PDF: institution_id=" << institution_id << " path=" << pdf_path.string()
              << "\n";
    const std::vector<ocr::Page> ocr_pages = backend.recognize(pdf_path);
    const std::vector<std::string> pages = statement::pages_to_text(ocr_pages);
    const std::string account_id =
        match_statement_to_account(pdf_path, pages, account_rows, account_id_override);
    const statement::StatementYear period = statement::extract_statement_year(pages);
    std::vector<statement::StatementTxn> txns =
        statement::parse_transactions(pages, period.year, period.month);
    const statement::SummaryTotals summary = statement::extract_summary(pages);

    const int64_t parsed_dep = sum_cents(txns, true);
    const int64_t parsed_wd = sum_cents(txns, false);
    std::cout << "Parsed statement: institution_id=" << institution_id << " account_id=" << account_id
              << " year=" << period.year << " month=" << period.month << " txn_count=" << txns.size()
              << " deposits=" << cents_to_string(parsed_dep)
              << " withdrawals=" << cents_to_string(parsed_wd) << "\n";
    if (summary.deposit_total) {
        const int64_t expected = persist::money_to_cents(*summary.deposit_total);
        if (parsed_dep != expected) {
            std::cerr << "WARNING: Deposit total mismatch institution_id=" << institution_id
                      << " parsed=" << cents_to_string(parsed_dep)
                      << " expected=" << *summary.deposit_total << "\n";
        }
    }
    if (summary.withdrawal_total) {
        const int64_t expected = persist::money_to_cents(*summary.withdrawal_total);
        if (parsed_wd != expected) {
            std::cerr << "WARNING: Withdrawal total mismatch institution_id=" << institution_id
                      << " parsed=" << cents_to_string(parsed_wd)
                      << " expected=" << *summary.withdrawal_total << "\n";
        }
    }
    return {account_id, std::move(txns)};
}

struct Counts {
    int inserted = 0;
    int skipped = 0;
    int parsed = 0;
};

Counts process_institution(db::Db& db, ocr::OcrBackend& backend, const fs::path& root,
                           const std::string& institution_id,
                           const std::optional<std::string>& account_id_override, bool dry_run) {
    const std::vector<fs::path> pdfs = pdfs_for_institution(root, institution_id);
    if (pdfs.empty()) {
        std::cerr << "WARNING: Skipping institution (no PDFs) institution_id=" << institution_id
                  << " expected_dir=" << (root / institution_id).string() << "\n";
        return {};
    }
    const std::vector<AccountRow> account_rows = accounts_for_institution(db, institution_id);

    std::map<std::string, std::vector<statement::StatementTxn>> by_account;
    for (const auto& pdf_path : pdfs) {
        ParsedStatement parsed =
            parse_statement_pdf(backend, pdf_path, institution_id, account_rows, account_id_override);
        auto& bucket = by_account[parsed.account_id];
        bucket.insert(bucket.end(), parsed.txns.begin(), parsed.txns.end());
    }

    Counts counts;
    for (const auto& [account_id, all_txns] : by_account) {
        counts.parsed += static_cast<int>(all_txns.size());
        std::cout << "Persisting account slice: institution_id=" << institution_id
                  << " account_id=" << account_id << " txn_count=" << all_txns.size() << "\n";
        const std::vector<persist::PlannedStatementTxn> planned =
            persist::plan_statement_transactions(db, account_id, all_txns);
        if (dry_run) {
            for (const auto& entry : planned) {
                if (entry.skipped_api_overlap) {
                    ++counts.skipped;
                    continue;
                }
                const std::string description = entry.txn.description.substr(
                    0, std::min<size_t>(entry.txn.description.size(), 80));
                std::cout << "  " << entry.txn.date << " " << std::setw(10) << std::right
                          << entry.txn.amount << " " << description << "\n";
                ++counts.inserted;
            }
            continue;
        }
        for (const auto& entry : planned) {
            if (entry.skipped_api_overlap) ++counts.skipped;
        }
        counts.inserted += persist::upsert_statement_transactions(db, account_id, planned);
    }
    return counts;
}

} // namespace

int main(int argc, char** argv) {
    Args args;
    try {
        if (!parse_args(argc, argv, args)) {
            std::cerr << "usage: teller_backfill [--institution-id <id>] [--account-id <id>] "
                         "[--statements-root <dir>] [--dry-run] [--debug]\n";
            return 2;
        }
    } catch (const ApiError& exc) {
        std::cerr << "teller_backfill: " << exc.detail() << "\n";
        return exc.status();
    }

    try {
        const fs::path root = statements_root(args.statements_root);
        const DbProfile profile = resolve_profile();
        std::unique_ptr<db::Db> database = db::open_from_profile(profile);
        std::unique_ptr<ocr::OcrBackend> backend = ocr::make_ocr_backend();

        const std::vector<std::string> institution_ids = list_institution_ids(*database, args.institution_id);
        if (institution_ids.empty()) {
            throw ApiError(1, "No institution_id values found in teller.account");
        }
        std::cout << "Institutions to process: count=" << institution_ids.size()
                  << " root=" << root.string() << "\n";

        Counts totals;
        for (const auto& institution_id : institution_ids) {
            const std::optional<std::string> override =
                (args.institution_id && *args.institution_id == institution_id) ? args.account_id
                                                                                : std::nullopt;
            const Counts counts = process_institution(*database, *backend, root, institution_id,
                                                       override, args.dry_run);
            totals.inserted += counts.inserted;
            totals.skipped += counts.skipped;
            totals.parsed += counts.parsed;
        }
        std::cout << "Backfill complete: inserted=" << totals.inserted
                  << " skipped=" << totals.skipped << " total_parsed=" << totals.parsed << "\n";
        return 0;
    } catch (const ApiError& exc) {
        std::cerr << "teller_backfill failed (" << exc.status() << "): " << exc.detail() << "\n";
        return 1;
    } catch (const std::exception& exc) {
        std::cerr << "teller_backfill failed: " << exc.what() << "\n";
        return 1;
    }
}
