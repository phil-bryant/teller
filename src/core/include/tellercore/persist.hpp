#pragma once

#include <cstdint>
#include <string>

#include <nlohmann/json.hpp>

#include "tellercore/db.hpp"
#include "tellercore/dialect.hpp"

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

} // namespace tellercore::persist
