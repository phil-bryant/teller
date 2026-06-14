#include "tellercore/statement.hpp"

#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <regex>
#include <string>
#include <utility>
#include <vector>

#include "tellercore/error.hpp"

// Direct port of 08_backfill_bank_statements.py. The Python script is the
// reference oracle; helper names and ordering follow it so the parity lane can
// diff the two implementations function-for-function.
namespace tellercore::statement {

namespace {

constexpr std::array<const char*, 5> kCreditPrefixes = {"DEPOSIT", "MOBILE DEPOSIT",
                                                        "INTEREST EARNED", "INTEREST", "ORIG:"};
constexpr std::array<const char*, 2> kCreditContains = {"RETURN", "REBATE"};

// (substring, normalized type). First substring hit wins; order matches Python.
const std::vector<std::pair<std::string, std::string>>& type_map() {
    static const std::vector<std::pair<std::string, std::string>> kMap = {
        {"POS PURCHASE", "card_payment"}, {"ATM WITHDRAWAL", "atm"},
        {"DEPOSIT", "deposit"},           {"MOBILE DEPOSIT", "deposit"},
        {"INTEREST", "interest"},         {"VERIZON/", "ach"},
        {"BILL PAY", "ach"},              {"WEB PAY", "ach"},
        {"ORIG:", "wire"},                {"INCOMING WIRE FEE", "fee"},
    };
    return kMap;
}

// std::regex objects are expensive to construct; build the fixed patterns once.
const std::regex kAmountRe(R"(((?:\d{1,3}(?:,\d{3})*|\d+)?\.\d{2})$)");
const std::regex kAnyAmountRe(R"(((?:\d{1,3}(?:,\d{3})*|\d+)?\.\d{2}))");
const std::regex kDateRe(R"(^(\d{1,2})/(\d{2})(?:\s+|$))");
const std::regex kInterestRe(R"(INTEREST EARNED\s+(\d{1,3}(?:,\d{3})*\.\d{2}))");
const std::regex kDateFullMatchRe(R"(\d{1,2}/\d{2})");
const std::regex kReturnCbaTailRe(R"((\d{2})$)");
const std::regex kStatementDateRe(R"(Statement Date\s+(\d{2})/(\d{2})/(\d{2}))");
const std::regex kDepositSummaryRe(R"(Deposits\s*/\s*Misc Credits\s+(\d+)\s+([\d,.]+))");
const std::regex kWithdrawalSummaryRe(R"(Withdrawals\s*/\s*Misc Debits\s+(\d+)\s+([\d,.]+))");
const std::regex kFilenameLastFourRe(R"(EStatement_(\d{4})_)", std::regex::icase);
const std::regex kLastFourStars(R"(\*{2,}\s*(\d{4})\b)");
const std::regex kLastFourAccount(R"((?:account|acct)\s*#?\s*\*{0,4}\s*(\d{4})\b)",
                                  std::regex::icase);
const std::regex kLastFourEnding(R"((?:ending|last)\s*(?:in|#|:)?\s*(\d{4})\b)", std::regex::icase);

constexpr const char* kWhitespace = " \t\n\r\f\v";

std::string rstrip(const std::string& s) {
    const auto end = s.find_last_not_of(kWhitespace);
    return end == std::string::npos ? "" : s.substr(0, end + 1);
}

std::string strip(const std::string& s) {
    const auto begin = s.find_first_not_of(kWhitespace);
    if (begin == std::string::npos) return "";
    const auto end = s.find_last_not_of(kWhitespace);
    return s.substr(begin, end - begin + 1);
}

std::string to_upper(const std::string& s) {
    std::string out = s;
    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    return out;
}

std::string to_lower(const std::string& s) {
    std::string out = s;
    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
}

bool starts_with(const std::string& s, const std::string& prefix) {
    return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
}

bool contains(const std::string& s, const std::string& needle) {
    return s.find(needle) != std::string::npos;
}

// Single non-overlapping left-to-right pass, matching Python str.replace().
std::string replace_all(const std::string& s, const std::string& from, const std::string& to) {
    if (from.empty()) return s;
    std::string out;
    out.reserve(s.size());
    size_t i = 0;
    while (i < s.size()) {
        if (s.compare(i, from.size(), from) == 0) {
            out += to;
            i += from.size();
        } else {
            out += s[i];
            ++i;
        }
    }
    return out;
}

std::string remove_commas(const std::string& s) { return replace_all(s, ",", ""); }

// Split on '\n', mirroring how page text built by reconstruct_lines is consumed
// by Python str.splitlines() for these single-newline-joined pages.
std::vector<std::string> split_lines(const std::string& page) {
    std::vector<std::string> out;
    std::string current;
    for (char c : page) {
        if (c == '\n') {
            out.push_back(current);
            current.clear();
        } else {
            current += c;
        }
    }
    if (!current.empty()) out.push_back(current);
    return out;
}

std::string two_digits(int value) {
    char buf[8];
    std::snprintf(buf, sizeof(buf), "%02d", value);
    return buf;
}

std::string format_date(int year, int month, int day) {
    return std::to_string(year) + "-" + two_digits(month) + "-" + two_digits(day);
}

int days_in_month(int year, int month) {
    static const std::array<int, 12> kDays = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    if (month == 2) {
        const bool leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
        return leap ? 29 : 28;
    }
    return kDays[static_cast<size_t>(month - 1)];
}

double median_sorted(std::vector<double>& gaps) {
    std::sort(gaps.begin(), gaps.end());
    const size_t middle = gaps.size() / 2;
    if (gaps.size() % 2 == 1) return gaps[middle];
    return (gaps[middle - 1] + gaps[middle]) / 2.0;
}

double adaptive_line_epsilon(const std::vector<double>& descending_ys, double min_epsilon,
                             double gap_factor) {
    std::vector<double> gaps;
    for (size_t index = 1; index < descending_ys.size(); ++index) {
        const double gap = std::abs(descending_ys[index - 1] - descending_ys[index]);
        if (gap > 0) gaps.push_back(gap);
    }
    double epsilon = min_epsilon;
    if (!gaps.empty()) {
        const double candidate = median_sorted(gaps) * gap_factor;
        if (candidate > epsilon) epsilon = candidate;
    }
    return epsilon;
}

std::string normalize_amount(const std::string& raw) {
    return starts_with(raw, ".") ? "0" + raw : raw;
}

// Last regex match of pattern in text, as {start, length, group1}.
struct LastMatch {
    bool found = false;
    size_t start = 0;
    size_t length = 0;
    std::string group1;
};

LastMatch last_match(const std::string& text, const std::regex& pattern) {
    LastMatch result;
    auto begin = std::sregex_iterator(text.begin(), text.end(), pattern);
    auto end = std::sregex_iterator();
    for (auto it = begin; it != end; ++it) {
        const std::smatch& m = *it;
        result.found = true;
        result.start = static_cast<size_t>(m.position(0));
        result.length = static_cast<size_t>(m.length(0));
        result.group1 = m[1].str();
    }
    return result;
}

struct AmountResult {
    bool found = false;
    std::string amount;
    int index = -1;
    std::string trimmed;
};

// Port of _find_amount: resolve the transaction amount field from grouped lines.
AmountResult find_amount(const std::vector<std::string>& lines) {
    for (size_t i = 0; i < lines.size(); ++i) {
        std::smatch m;
        if (std::regex_search(lines[i], m, kAmountRe)) {
            return {true, normalize_amount(m[1].str()), static_cast<int>(i),
                    rstrip(lines[i].substr(0, static_cast<size_t>(m.position(0))))};
        }
    }
    for (size_t i = 0; i < lines.size(); ++i) {
        const LastMatch m = last_match(lines[i], kAnyAmountRe);
        if (m.found) {
            const std::string merged =
                lines[i].substr(0, m.start) + lines[i].substr(m.start + m.length);
            return {true, normalize_amount(m.group1), static_cast<int>(i),
                    strip(replace_all(merged, "  ", " "))};
        }
    }
    std::string joined;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (i) joined += " ";
        joined += lines[i];
    }
    const LastMatch jm = last_match(joined, kAnyAmountRe);
    if (jm.found) {
        return {true, normalize_amount(jm.group1), static_cast<int>(lines.size()) - 1,
                rstrip(joined.substr(0, jm.start))};
    }
    for (size_t i = 0; i < lines.size(); ++i) {
        std::smatch m;
        if (contains(lines[i], "RETURN CBA FEES") &&
            std::regex_search(lines[i], m, kReturnCbaTailRe)) {
            return {true, "0." + m[1].str(), static_cast<int>(i),
                    rstrip(lines[i].substr(0, static_cast<size_t>(m.position(0))))};
        }
    }
    return {};
}

std::vector<std::string> extract_activity_lines(const std::vector<std::string>& pages) {
    std::vector<std::string> all_lines;
    for (const auto& page : pages) {
        bool in_section = false;
        for (const auto& line : split_lines(page)) {
            const std::string s = strip(line);
            const std::string lower = to_lower(s);
            const bool has_header_terms =
                contains(lower, "date") && contains(lower, "activity") &&
                contains(lower, "description");
            if (has_header_terms) {
                in_section = true;
            } else if (in_section && !s.empty()) {
                all_lines.push_back(s);
            }
        }
    }
    return all_lines;
}

std::vector<std::string> merge_split_date_lines(const std::vector<std::string>& all_lines) {
    std::vector<std::string> normalized;
    size_t i = 0;
    while (i < all_lines.size()) {
        const std::string& s = all_lines[i];
        if (std::regex_match(s, kDateFullMatchRe) && i + 1 < all_lines.size()) {
            normalized.push_back(s + " " + all_lines[i + 1]);
            i += 2;
            continue;
        }
        normalized.push_back(s);
        ++i;
    }
    return normalized;
}

struct TransactionGroup {
    int month = 0;
    int day = 0;
    std::vector<std::string> lines;
};

std::vector<TransactionGroup> group_transaction_lines(
    const std::vector<std::string>& normalized_lines) {
    std::vector<TransactionGroup> groups;
    bool have_current = false;
    TransactionGroup current;
    for (const auto& line : normalized_lines) {
        std::smatch dm;
        if (std::regex_search(line, dm, kDateRe)) {
            if (have_current) groups.push_back(current);
            const std::string tail = strip(line.substr(static_cast<size_t>(dm.length(0))));
            current = TransactionGroup{};
            current.month = std::stoi(dm[1].str());
            current.day = std::stoi(dm[2].str());
            if (!tail.empty()) current.lines.push_back(tail);
            have_current = true;
        } else if (have_current) {
            current.lines.push_back(line);
        }
    }
    if (have_current) groups.push_back(current);
    return groups;
}

bool is_credit(const std::string& desc_upper) {
    for (const char* prefix : kCreditPrefixes) {
        if (starts_with(desc_upper, prefix)) return true;
    }
    for (const char* token : kCreditContains) {
        if (contains(desc_upper, token)) return true;
    }
    return false;
}

std::optional<StatementTxn> transaction_from_group(const TransactionGroup& group, int year) {
    const AmountResult amount = find_amount(group.lines);
    if (!amount.found) return std::nullopt;
    std::vector<std::string> desc_parts;
    for (size_t line_index = 0; line_index < group.lines.size(); ++line_index) {
        desc_parts.push_back(static_cast<int>(line_index) == amount.index ? amount.trimmed
                                                                          : group.lines[line_index]);
    }
    std::string description;
    for (const auto& part : desc_parts) {
        if (part.empty()) continue;
        if (!description.empty()) description += " ";
        description += part;
    }
    const std::string amount_clean = remove_commas(amount.amount);
    const std::string desc_upper = to_upper(description);
    const std::string signed_amount = is_credit(desc_upper) ? amount_clean : "-" + amount_clean;
    return StatementTxn{format_date(year, group.month, group.day), signed_amount, description,
                        infer_type(description)};
}

void rescue_buried_interest(std::vector<StatementTxn>& result,
                            const std::vector<TransactionGroup>& groups, int year, int stmt_month) {
    for (const auto& txn : result) {
        if (starts_with(txn.description, "INTEREST")) return;
    }
    for (const auto& group : groups) {
        std::string full_text;
        for (size_t i = 0; i < group.lines.size(); ++i) {
            if (i) full_text += " ";
            full_text += group.lines[i];
        }
        std::smatch m;
        if (std::regex_search(full_text, m, kInterestRe)) {
            const int last_day = days_in_month(year, stmt_month);
            result.push_back(StatementTxn{format_date(year, stmt_month, last_day),
                                          remove_commas(m[1].str()), "INTEREST EARNED", "interest"});
            return;
        }
    }
}

// SHA-256 lowercase hex digest via the OpenSSL EVP interface (SHA256() is
// deprecated in OpenSSL 3 and trips -Werror).
std::string sha256_hex(const std::string& input) {
    std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
    unsigned int digest_len = 0;
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx) throw ApiError(500, "failed to allocate SHA-256 context");
    bool ok = EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr) == 1 &&
              EVP_DigestUpdate(ctx, input.data(), input.size()) == 1 &&
              EVP_DigestFinal_ex(ctx, digest.data(), &digest_len) == 1;
    EVP_MD_CTX_free(ctx);
    if (!ok) throw ApiError(500, "SHA-256 digest failed");
    static const char* kHex = "0123456789abcdef";
    std::string out;
    out.reserve(static_cast<size_t>(digest_len) * 2);
    for (unsigned int i = 0; i < digest_len; ++i) {
        out += kHex[digest[i] >> 4];
        out += kHex[digest[i] & 0x0F];
    }
    return out;
}

} // namespace

std::vector<std::string> reconstruct_lines(const ocr::Page& points, double min_epsilon,
                                           double gap_factor) {
    std::vector<ocr::Observation> ordered(points.begin(), points.end());
    // sorted(points, key=lambda p: (-y, x)) with Python's stable ordering.
    std::stable_sort(ordered.begin(), ordered.end(),
                     [](const ocr::Observation& a, const ocr::Observation& b) {
                         if (a.y != b.y) return a.y > b.y;
                         return a.x < b.x;
                     });
    std::vector<double> ys;
    ys.reserve(ordered.size());
    for (const auto& p : ordered) ys.push_back(p.y);
    const double epsilon = adaptive_line_epsilon(ys, min_epsilon, gap_factor);

    struct Line {
        double y;
        std::vector<std::pair<double, std::string>> chunks;
    };
    std::vector<Line> lines;
    for (const auto& p : ordered) {
        if (lines.empty() || std::abs(lines.back().y - p.y) > epsilon) {
            lines.push_back(Line{p.y, {{p.x, p.text}}});
        } else {
            lines.back().chunks.emplace_back(p.x, p.text);
        }
    }
    std::vector<std::string> page_lines;
    page_lines.reserve(lines.size());
    for (auto& ln : lines) {
        std::stable_sort(ln.chunks.begin(), ln.chunks.end(),
                         [](const auto& a, const auto& b) { return a.first < b.first; });
        std::string joined;
        for (size_t i = 0; i < ln.chunks.size(); ++i) {
            if (i) joined += " ";
            joined += ln.chunks[i].second;
        }
        page_lines.push_back(joined);
    }
    return page_lines;
}

std::vector<std::string> pages_to_text(const std::vector<ocr::Page>& pages) {
    std::vector<std::string> out;
    out.reserve(pages.size());
    for (const auto& page : pages) {
        const std::vector<std::string> lines = reconstruct_lines(page);
        std::string joined;
        for (size_t i = 0; i < lines.size(); ++i) {
            if (i) joined += "\n";
            joined += lines[i];
        }
        out.push_back(joined);
    }
    return out;
}

StatementYear extract_statement_year(const std::vector<std::string>& pages) {
    for (const auto& page : pages) {
        std::smatch m;
        if (std::regex_search(page, m, kStatementDateRe)) {
            return StatementYear{2000 + std::stoi(m[3].str()), std::stoi(m[1].str())};
        }
    }
    throw ApiError(422, "Could not find Statement Date in PDF");
}

SummaryTotals extract_summary(const std::vector<std::string>& pages) {
    SummaryTotals totals;
    for (const auto& page : pages) {
        std::smatch m;
        if (std::regex_search(page, m, kDepositSummaryRe)) {
            totals.deposit_count = std::stoi(m[1].str());
            totals.deposit_total = remove_commas(m[2].str());
        }
        if (std::regex_search(page, m, kWithdrawalSummaryRe)) {
            totals.withdrawal_count = std::stoi(m[1].str());
            totals.withdrawal_total = remove_commas(m[2].str());
        }
    }
    return totals;
}

std::string infer_type(const std::string& description) {
    for (const auto& [prefix, ttype] : type_map()) {
        if (contains(description, prefix)) return ttype;
    }
    return "unknown";
}

std::vector<StatementTxn> parse_transactions(const std::vector<std::string>& pages, int year,
                                             int stmt_month) {
    const std::vector<std::string> all_lines = extract_activity_lines(pages);
    const std::vector<std::string> normalized_lines = merge_split_date_lines(all_lines);
    const std::vector<TransactionGroup> groups = group_transaction_lines(normalized_lines);
    std::vector<StatementTxn> result;
    for (const auto& group : groups) {
        if (auto record = transaction_from_group(group, year)) result.push_back(*record);
    }
    rescue_buried_interest(result, groups, year, stmt_month);
    return result;
}

std::optional<std::string> extract_last_four_hint(const std::string& pdf_filename,
                                                  const std::vector<std::string>& pages) {
    std::smatch m;
    if (std::regex_search(pdf_filename, m, kFilenameLastFourRe)) return m[1].str();
    std::string head;
    for (size_t i = 0; i < pages.size() && i < 3; ++i) {
        if (i) head += "\n";
        head += pages[i];
    }
    for (const std::regex* rx : {&kLastFourStars, &kLastFourAccount, &kLastFourEnding}) {
        if (std::regex_search(head, m, *rx)) return m[1].str();
    }
    return std::nullopt;
}

std::string make_txn_id(const std::string& account_id, const std::string& date_str,
                        const std::string& amount, const std::string& description, int occurrence) {
    const std::string payload = account_id + "|" + date_str + "|" + amount + "|" + description +
                                "|" + std::to_string(occurrence);
    return "stmt_" + sha256_hex(payload).substr(0, 20);
}

} // namespace tellercore::statement
