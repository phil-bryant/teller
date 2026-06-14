#pragma once

#include <optional>
#include <string>
#include <vector>

#include "tellercore/ocr.hpp"

// Platform-agnostic bank-statement parser: the portable C++ port of
// 08_backfill_bank_statements.py. Everything here operates on OCR observations
// or already-reconstructed page text, so it compiles and is tested identically
// on every platform. The retired Python script remains the reference oracle.
namespace tellercore::statement {

// One parsed statement transaction. amount is a signed decimal string with the
// thousands separators stripped ("-1234.56", "12.00"), matching the dict the
// Python parser emits before persistence.
struct StatementTxn {
    std::string date;         // YYYY-MM-DD
    std::string amount;       // signed decimal string
    std::string description;
    std::string type;
};

// Statement period derived from the "Statement Date MM/DD/YY" marker.
struct StatementYear {
    int year = 0;
    int month = 0;
};

// Deposit/withdrawal control totals scraped from the statement summary block.
// Totals are decimal strings (thousands separators stripped); absent fields
// stay nullopt, mirroring the Python tuple of optionals.
struct SummaryTotals {
    std::optional<int> deposit_count;
    std::optional<std::string> deposit_total;
    std::optional<int> withdrawal_count;
    std::optional<std::string> withdrawal_total;
};

// Reconstruct page text lines from OCR observations via adaptive 1-D density
// clustering on the y-axis (port of reconstruct_lines / _adaptive_line_epsilon).
// Chunks within each clustered line are ordered left-to-right by x.
std::vector<std::string> reconstruct_lines(const ocr::Page& points, double min_epsilon = 0.004,
                                           double gap_factor = 0.6);

// Reconstruct every page into a single '\n'-joined text string (one per page),
// the representation the rest of the parser consumes.
std::vector<std::string> pages_to_text(const std::vector<ocr::Page>& pages);

// Extract statement year/month from the "Statement Date" marker. Throws
// ApiError(422) when no statement date is found (Python ValueError parity).
StatementYear extract_statement_year(const std::vector<std::string>& pages);

// Scrape deposit/withdrawal summary counts and totals from the summary block.
SummaryTotals extract_summary(const std::vector<std::string>& pages);

// Infer the normalized transaction type from description prefixes.
std::string infer_type(const std::string& description);

// Parse transaction rows from reconstructed page text, inferring signed amounts
// and types, and rescuing buried interest rows.
std::vector<StatementTxn> parse_transactions(const std::vector<std::string>& pages, int year,
                                             int stmt_month);

// Extract the account last-four hint from the PDF filename, then the OCR head
// text. Returns nullopt when nothing matches.
std::optional<std::string> extract_last_four_hint(const std::string& pdf_filename,
                                                   const std::vector<std::string>& pages);

// Build the deterministic statement transaction id:
//   "stmt_" + lower-hex(sha256(account|date|amount|description|occurrence))[:20]
std::string make_txn_id(const std::string& account_id, const std::string& date_str,
                        const std::string& amount, const std::string& description,
                        int occurrence = 1);

} // namespace tellercore::statement
