#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "tellercore/db.hpp"
#include "tellercore/dialect.hpp"
#include "tellercore/statement.hpp"

namespace tellercore::persist {

using nlohmann::json;

// USD money string ("12.34", "-5.00") -> integer minor units (cents), rounding
// half-up at the cent, mirroring teller_persist._sqlite_money_to_minor_units.
int64_t money_to_cents(const std::string& value);

// Idempotent ingestion of Teller API payloads, port of
// teller_persist.persist_all. Upserts accounts/institutions, the identity
// graph, balances and transactions, canonicalizes duplicate transaction ids
// (posted wins over pending), reconciles stale pending transactions, prunes
// unreferenced relation rows, then commits once. Rolls back and rethrows on
// any error. SQLite stores money as integer cents; Postgres stores decimal.
void persist_all(db::Db& db, const json& raw_identities,
                 const json& raw_transactions_by_account,
                 const json& raw_balances_by_account = json::object());

// A statement transaction resolved to its deterministic id and API-overlap
// decision. Port of the per-row bookkeeping in
// 08_backfill_bank_statements._persist_account_transactions.
struct PlannedStatementTxn {
    std::string transaction_id;        // make_txn_id(account, date, amount, desc, occurrence)
    statement::StatementTxn txn;       // parsed date/amount/description/type
    int occurrence = 1;                // 1-based count of identical (date,amount,desc) rows
    bool skipped_api_overlap = false;  // date >= earliest 'txn_%' API date for this account
};

// Assign deterministic ids and the API-overlap skip decision to a batch of
// parsed statement transactions for one account. Reads the earliest live Teller
// API transaction date (transaction_id LIKE 'txn_%') and flags backfilled rows
// on or after it as skipped, so statement backfill never overwrites API data.
// occurrence is the running count of identical (date, amount, description) keys,
// matching the Python seen_occurrences map. No rows are written.
std::vector<PlannedStatementTxn> plan_statement_transactions(
    db::Db& db, const std::string& account_id,
    const std::vector<statement::StatementTxn>& txns);

// Upsert every non-skipped planned transaction for one account in a single DB
// transaction (commit on success, rollback + rethrow on error). Each row is
// persisted as a posted statement transaction (status 'posted', stmt:// self
// link, null running balance/category/counterparty), reusing the same upsert
// path and money_to_cents conversion as the Teller API ingest. Returns the
// number of rows upserted.
int upsert_statement_transactions(db::Db& db, const std::string& account_id,
                                  const std::vector<PlannedStatementTxn>& planned);

} // namespace tellercore::persist
