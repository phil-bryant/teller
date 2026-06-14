// NOLINTBEGIN(bugprone-easily-swappable-parameters)
#include "tellercore/persist.hpp"

#include <map>
#include <optional>
#include <stdexcept>
#include <tuple>
#include <vector>

#include "tellercore/error.hpp"
#include "tellercore/statement.hpp"

namespace tellercore::persist {

namespace {

using db::Db;
using db::Params;
using db::Row;
using db::Value;

// #R001: Traceability for function `is_sqlite`.
bool is_sqlite(Db& db) { return db.dialect() == Dialect::kSqlite; }

// JSON scalar -> bound Value. null/missing collapses to SQL NULL.
// #R001: Traceability for function `json_to_value`.
Value json_to_value(const json& v) {
    if (v.is_null()) return std::monostate{};
    if (v.is_boolean()) return static_cast<int64_t>(v.get<bool>() ? 1 : 0);
    if (v.is_number_integer()) return v.get<int64_t>();
    if (v.is_number_unsigned()) return static_cast<int64_t>(v.get<uint64_t>());
    if (v.is_number_float()) return v.get<double>();
    if (v.is_string()) return v.get<std::string>();
    return v.dump();
}

// Required string field (Python KeyError parity: throws when absent).
// #R001: Traceability for function `require_str`.
std::string require_str(const json& obj, const char* key) {
    if (!obj.contains(key) || obj[key].is_null()) {
        throw ApiError(422, std::string("missing required field: ") + key);
    }
    if (obj[key].is_string()) return obj[key].get<std::string>();
    return obj[key].dump();
}

// Optional field as a bound Value (NULL when absent/null).
// #R001: Traceability for function `opt_value`.
Value opt_value(const json& obj, const char* key) {
    auto it = obj.find(key);
    if (it == obj.end()) return std::monostate{};
    return json_to_value(*it);
}

// Optional string with default, used for HATEOAS link fields (Python .get(key, "")).
// #R001: Traceability for function `opt_str`.
std::string opt_str(const json& obj, const char* key, const std::string& fallback = "") {
    auto it = obj.find(key);
    if (it == obj.end() || it->is_null()) return fallback;
    if (it->is_string()) return it->get<std::string>();
    return it->dump();
}

// #R001: Traceability for function `truthy_money`.
bool truthy_money(const json& obj, const char* key) {
    auto it = obj.find(key);
    if (it == obj.end() || it->is_null()) return false;
    if (it->is_string()) return !it->get<std::string>().empty();
    if (it->is_number()) return it->get<double>() != 0.0;
    return false;
}

// Money string -> bound Value for the active backend: integer cents on SQLite,
// the original decimal text on Postgres (libpq coerces it into numeric).
// #R001: Traceability for function `money_value`.
Value money_value(Db& db, const json& obj, const char* key) {
    if (!truthy_money(obj, key)) return std::monostate{};
    const std::string raw = obj[key].is_string() ? obj[key].get<std::string>() : obj[key].dump();
    if (is_sqlite(db)) return money_to_cents(raw);
    return raw;
}

// Currency guard: SQLite stores integer cents under a USD assumption.
// #R001: Traceability for function `require_usd_for_sqlite`.
void require_usd_for_sqlite(Db& db, const std::string& currency, const std::string& account_id) {
    if (is_sqlite(db) && currency != "USD") {
        throw ApiError(422, "SQLite money storage expects USD accounts; got currency=" + currency +
                                " account_id=" + account_id);
    }
}

// INSERT helper that returns the generated primary key on both backends. Uses
// RETURNING (SQLite >= 3.35 / SQLCipher; Postgres) rather than last_insert_rowid:
// the latter is wrong for "INSERT ... ON CONFLICT DO UPDATE" when a conflict
// resolves to an UPDATE (no insert), where it yields a stale rowid and the
// caller then writes a dangling foreign key. RETURNING reports the upserted
// row's id correctly on both the insert and update paths (teller_persist parity).
// #R001: Traceability for function `insert_returning_id`.
int64_t insert_returning_id(Db& db, const std::string& insert_sql, const std::string& id_col,
                            const Params& params) {
    auto row = db.query_one(insert_sql + " RETURNING " + id_col, params);
    if (!row) throw ApiError(500, "insert did not return id for " + id_col);
    return row->get_int(id_col).value_or(0);
}

// #R001: Traceability for function `scalar_int`.
std::optional<int64_t> scalar_int(Db& db, const std::string& sql, const Params& params,
                                  const std::string& col) {
    auto row = db.query_one(sql, params);
    if (!row || row->is_null(col)) return std::nullopt;
    return row->get_int(col);
}

// Builds "IN (:p0, :p1, ...)" with the supplied prefix and fills params.
// #R001: Traceability for function `in_clause`.
std::string in_clause(const std::vector<std::string>& ids, const std::string& prefix,
                      Params& params) {
    std::string out = "(";
    for (size_t i = 0; i < ids.size(); ++i) {
        const std::string name = prefix + std::to_string(i);
        if (i) out += ", ";
        out += ":" + name;
        params.emplace(name, ids[i]);
    }
    out += ")";
    return out;
}

// #R001: Traceability for function `upsert_institution`.
void upsert_institution(Db& db, const json& inst) {
    db.execute(
        "INSERT INTO teller.institution (institution_id, name) VALUES (:id, :name) "
        "ON CONFLICT (institution_id) DO UPDATE SET name = EXCLUDED.name",
        {{"id", require_str(inst, "id")}, {"name", require_str(inst, "name")}});
}

// #R001: Traceability for function `upsert_account_links`.
int64_t upsert_account_links(Db& db, const json& links, std::optional<int64_t> existing_id) {
    Params vals{{"self_link", opt_str(links, "self")},
                {"details", opt_value(links, "details")},
                {"balances", opt_value(links, "balances")},
                {"transactions", opt_value(links, "transactions")}};
    if (existing_id) {
        vals.emplace("id", *existing_id);
        db.execute(
            "UPDATE teller.account_links SET self_link = :self_link, details = :details, "
            "balances = :balances, transactions = :transactions WHERE account_links_id = :id",
            vals);
        return *existing_id;
    }
    return insert_returning_id(
        db,
        "INSERT INTO teller.account_links (self_link, details, balances, transactions) "
        "VALUES (:self_link, :details, :balances, :transactions)",
        "account_links_id", vals);
}

// #R001: Traceability for function `upsert_account`.
void upsert_account(Db& db, const json& account) {
    const std::string acct_id = require_str(account, "id");
    const std::string currency = require_str(account, "currency");
    require_usd_for_sqlite(db, currency, acct_id);
    const json& inst = account.at("institution");
    upsert_institution(db, inst);
    auto existing = scalar_int(
        db, "SELECT account_links_id FROM teller.account WHERE account_id = :id",
        {{"id", acct_id}}, "account_links_id");
    const int64_t links_id = upsert_account_links(db, account.at("links"), existing);
    Params vals{{"account_id", acct_id},
                {"currency", currency},
                {"enrollment_id", require_str(account, "enrollment_id")},
                {"institution_id", require_str(inst, "id")},
                {"last_four", require_str(account, "last_four")},
                {"account_links_id", links_id},
                {"name", require_str(account, "name")},
                {"type", require_str(account, "type")},
                {"subtype", require_str(account, "subtype")},
                {"status", require_str(account, "status")}};
    db.execute(
        "INSERT INTO teller.account (account_id, currency, enrollment_id, institution_id, "
        "last_four, account_links_id, name, type, subtype, status) "
        "VALUES (:account_id, :currency, :enrollment_id, :institution_id, :last_four, "
        ":account_links_id, :name, :type, :subtype, :status) "
        "ON CONFLICT (account_id) DO UPDATE SET currency = EXCLUDED.currency, "
        "enrollment_id = EXCLUDED.enrollment_id, institution_id = EXCLUDED.institution_id, "
        "last_four = EXCLUDED.last_four, name = EXCLUDED.name, type = EXCLUDED.type, "
        "subtype = EXCLUDED.subtype, status = EXCLUDED.status",
        vals);
}

// #R001: Traceability for function `existing_identity_by_email`.
std::optional<int64_t> existing_identity_by_email(Db& db, const json& emails) {
    for (const auto& email : emails) {
        auto id = scalar_int(
            db, "SELECT identity_id FROM teller.identity_email WHERE data = :data",
            {{"data", require_str(email, "data")}}, "identity_id");
        if (id) return id;
    }
    return std::nullopt;
}

// #R001: Traceability for function `upsert_identity_record`.
int64_t upsert_identity_record(Db& db, const std::string& owner_type,
                               std::optional<int64_t> identity_id) {
    if (identity_id) {
        db.execute("UPDATE teller.identity SET type = :type WHERE identity_id = :id",
                   {{"type", owner_type}, {"id", *identity_id}});
        return *identity_id;
    }
    return insert_returning_id(db, "INSERT INTO teller.identity (type) VALUES (:type)",
                               "identity_id", {{"type", owner_type}});
}

// #R001: Traceability for function `upsert_identity_names`.
void upsert_identity_names(Db& db, const json& names, int64_t identity_id) {
    for (const auto& n : names) {
        db.execute(
            "INSERT INTO teller.identity_name (type, data, identity_id) "
            "VALUES (:type, :data, :identity_id) "
            "ON CONFLICT (data, identity_id) DO UPDATE SET type = EXCLUDED.type",
            {{"type", require_str(n, "type")}, {"data", require_str(n, "data")},
             {"identity_id", identity_id}});
    }
}

// #R001: Traceability for function `upsert_identity_emails`.
void upsert_identity_emails(Db& db, const json& emails, int64_t identity_id) {
    for (const auto& e : emails) {
        db.execute(
            "INSERT INTO teller.identity_email (data, identity_id) VALUES (:data, :identity_id) "
            "ON CONFLICT (data) DO NOTHING",
            {{"data", require_str(e, "data")}, {"identity_id", identity_id}});
    }
}

// #R001: Traceability for function `upsert_identity_phone_numbers`.
void upsert_identity_phone_numbers(Db& db, const json& phones, int64_t identity_id) {
    for (const auto& p : phones) {
        db.execute(
            "INSERT INTO teller.identity_phone_number (type, data, identity_id) "
            "VALUES (:type, :data, :identity_id) "
            "ON CONFLICT (data, identity_id) DO UPDATE SET type = EXCLUDED.type",
            {{"type", require_str(p, "type")}, {"data", require_str(p, "data")},
             {"identity_id", identity_id}});
    }
}

// #R001: Traceability for function `upsert_identity_addresses`.
void upsert_identity_addresses(Db& db, const json& addresses, int64_t identity_id) {
    for (const auto& a : addresses) {
        const json& addr = a.at("data");
        const int64_t addr_data_id = insert_returning_id(
            db,
            "INSERT INTO teller.identity_address_data (street, city, region, country, postal_code) "
            "VALUES (:street, :city, :region, :country, :postal_code) "
            "ON CONFLICT (street, city, region, country, postal_code) DO UPDATE SET street = EXCLUDED.street",
            "identity_address_data_id",
            {{"street", opt_value(addr, "street")}, {"city", opt_value(addr, "city")},
             {"region", opt_value(addr, "region")}, {"country", opt_value(addr, "country")},
             {"postal_code", opt_value(addr, "postal_code")}});
        const bool primary = a.value("primary", false);
        db.execute(
            "INSERT INTO teller.identity_address (primary_address, identity_address_data_id, identity_id) "
            "VALUES (:primary, :addr_data_id, :identity_id) "
            "ON CONFLICT (identity_address_data_id, identity_id) DO UPDATE SET "
            "primary_address = EXCLUDED.primary_address",
            {{"primary", static_cast<int64_t>(primary ? 1 : 0)},
             {"addr_data_id", addr_data_id}, {"identity_id", identity_id}});
    }
}

// #R001: Traceability for function `upsert_identity`.
int64_t upsert_identity(Db& db, const json& owner) {
    const json emails = owner.contains("emails") && !owner["emails"].is_null() ? owner["emails"]
                                                                               : json::array();
    std::optional<int64_t> identity_id = existing_identity_by_email(db, emails);
    identity_id = upsert_identity_record(db, require_str(owner, "type"), identity_id);
    const auto arr = [&](const char* key) {
        return owner.contains(key) && !owner[key].is_null() ? owner[key] : json::array();
    };
    upsert_identity_names(db, arr("names"), *identity_id);
    upsert_identity_emails(db, emails, *identity_id);
    upsert_identity_phone_numbers(db, arr("phone_numbers"), *identity_id);
    upsert_identity_addresses(db, arr("addresses"), *identity_id);
    return *identity_id;
}

// #R001: Traceability for function `upsert_account_identity`.
void upsert_account_identity(Db& db, const std::string& account_id, int64_t identity_id) {
    db.execute(
        "INSERT INTO teller.account_identities (account_id, identity_id) "
        "VALUES (:account_id, :identity_id) ON CONFLICT (account_id, identity_id) DO NOTHING",
        {{"account_id", account_id}, {"identity_id", identity_id}});
}

// #R001: Traceability for function `upsert_transaction_type`.
int64_t upsert_transaction_type(Db& db, const std::string& code) {
    auto existing = scalar_int(
        db, "SELECT transaction_type_id FROM teller.transaction_type WHERE code = :code",
        {{"code", code}}, "transaction_type_id");
    if (existing) return *existing;
    return insert_returning_id(db, "INSERT INTO teller.transaction_type (code) VALUES (:code)",
                               "transaction_type_id", {{"code", code}});
}

// #R001: Traceability for function `upsert_transaction_links`.
int64_t upsert_transaction_links(Db& db, const json& links, std::optional<int64_t> existing_id) {
    const std::string self_link = opt_str(links, "self");
    const std::string account_link = opt_str(links, "account");
    if (existing_id) {
        db.execute(
            "UPDATE teller.transaction_links SET self_link = :self_link, account = :account "
            "WHERE transaction_links_id = :id",
            {{"self_link", self_link}, {"account", account_link}, {"id", *existing_id}});
        return *existing_id;
    }
    auto row = scalar_int(
        db, "SELECT transaction_links_id FROM teller.transaction_links WHERE self_link = :sl",
        {{"sl", self_link}}, "transaction_links_id");
    if (row) return *row;
    return insert_returning_id(
        db,
        "INSERT INTO teller.transaction_links (self_link, account) VALUES (:self_link, :account) "
        "ON CONFLICT (self_link) DO UPDATE SET account = EXCLUDED.account",
        "transaction_links_id", {{"self_link", self_link}, {"account", account_link}});
}

// #R001: Traceability for function `upsert_transaction_details`.
int64_t upsert_transaction_details(Db& db, const json& details, std::optional<int64_t> existing_id) {
    Value counterparty_id = std::monostate{};
    auto cp_it = details.find("counterparty");
    if (cp_it != details.end() && cp_it->is_object() && cp_it->contains("name") &&
        !(*cp_it)["name"].is_null() &&
        !((*cp_it)["name"].is_string() && (*cp_it)["name"].get<std::string>().empty())) {
        const std::string name = require_str(*cp_it, "name");
        const std::string type = require_str(*cp_it, "type");
        auto found = scalar_int(
            db,
            "SELECT transaction_details_counterparty_id FROM teller.transaction_details_counterparty "
            "WHERE name = :name AND type = :type",
            {{"name", name}, {"type", type}}, "transaction_details_counterparty_id");
        if (found) {
            counterparty_id = *found;
        } else {
            counterparty_id = insert_returning_id(
                db,
                "INSERT INTO teller.transaction_details_counterparty (name, type) "
                "VALUES (:name, :type)",
                "transaction_details_counterparty_id", {{"name", name}, {"type", type}});
        }
    }
    Params vals{{"processing_status", require_str(details, "processing_status")},
                {"category", opt_value(details, "category")},
                {"transaction_details_counterparty_id", counterparty_id}};
    if (existing_id) {
        vals.emplace("id", *existing_id);
        db.execute(
            "UPDATE teller.transaction_details SET processing_status = :processing_status, "
            "category = :category, "
            "transaction_details_counterparty_id = :transaction_details_counterparty_id "
            "WHERE transaction_details_id = :id",
            vals);
        return *existing_id;
    }
    return insert_returning_id(
        db,
        "INSERT INTO teller.transaction_details (processing_status, category, "
        "transaction_details_counterparty_id) "
        "VALUES (:processing_status, :category, :transaction_details_counterparty_id)",
        "transaction_details_id", vals);
}

// #R001: Traceability for function `upsert_transaction`.
void upsert_transaction(Db& db, const json& txn) {
    const std::string txn_id = require_str(txn, "id");
    auto existing = db.query_one(
        "SELECT transaction_details_id, transaction_links_id FROM teller.\"transaction\" "
        "WHERE transaction_id = :id",
        {{"id", txn_id}});
    std::optional<int64_t> existing_details =
        existing ? existing->get_int("transaction_details_id") : std::nullopt;
    std::optional<int64_t> existing_links =
        existing ? existing->get_int("transaction_links_id") : std::nullopt;
    const int64_t type_id = upsert_transaction_type(db, require_str(txn, "type"));
    const int64_t details_id = upsert_transaction_details(db, txn.at("details"), existing_details);
    const int64_t links_id = upsert_transaction_links(db, txn.at("links"), existing_links);
    Params vals{{"transaction_id", txn_id},
                {"account_id", require_str(txn, "account_id")},
                {"amount", money_value(db, txn, "amount")},
                {"date", require_str(txn, "date")},
                {"description", require_str(txn, "description")},
                {"transaction_details_id", details_id},
                {"status", require_str(txn, "status")},
                {"transaction_links_id", links_id},
                {"running_balance", money_value(db, txn, "running_balance")},
                {"transaction_type_id", type_id}};
    db.execute(
        "INSERT INTO teller.\"transaction\" (transaction_id, account_id, amount, date, description, "
        "transaction_details_id, status, transaction_links_id, running_balance, transaction_type_id) "
        "VALUES (:transaction_id, :account_id, :amount, :date, :description, :transaction_details_id, "
        ":status, :transaction_links_id, :running_balance, :transaction_type_id) "
        "ON CONFLICT (transaction_id) DO UPDATE SET account_id = EXCLUDED.account_id, "
        "amount = EXCLUDED.amount, date = EXCLUDED.date, description = EXCLUDED.description, "
        "transaction_details_id = EXCLUDED.transaction_details_id, status = EXCLUDED.status, "
        "transaction_links_id = EXCLUDED.transaction_links_id, "
        "running_balance = EXCLUDED.running_balance, "
        "transaction_type_id = EXCLUDED.transaction_type_id, updated_at = CURRENT_TIMESTAMP",
        vals);
}

// posted snapshots win over pending for duplicate ids, preserving order.
// #R001: Traceability for function `canonicalize_transactions`.
std::vector<json> canonicalize_transactions(const json& txns) {
    std::vector<json> ordered;
    std::vector<std::string> id_order;
    std::map<std::string, size_t> index_of;
    for (const auto& txn : txns) {
        const std::string id = require_str(txn, "id");
        auto it = index_of.find(id);
        if (it == index_of.end()) {
            index_of.emplace(id, ordered.size());
            ordered.push_back(txn);
            id_order.push_back(id);
            continue;
        }
        const std::string existing_status = ordered[it->second].value("status", "");
        const std::string incoming_status = txn.value("status", "");
        if (existing_status != "posted" && incoming_status == "posted") {
            ordered[it->second] = txn;
        }
    }
    return ordered;
}

// #R001: Traceability for function `reconcile_missing_pending`.
std::vector<std::string> reconcile_missing_pending(Db& db, const std::string& account_id,
                                                   const std::vector<std::string>& fetched_ids) {
    if (fetched_ids.empty()) return {};
    Params params{{"account_id", account_id}};
    const std::string in_list = in_clause(fetched_ids, "fid", params);
    auto stale = db.query(
        "SELECT transaction_id FROM teller.\"transaction\" WHERE account_id = :account_id "
        "AND status = 'pending' AND transaction_id NOT IN " + in_list,
        params);
    std::vector<std::string> deleted;
    for (const auto& row : stale) {
        if (auto id = row.get_text("transaction_id")) deleted.push_back(*id);
    }
    if (deleted.empty()) return {};
    Params del_params{{"account_id", account_id}};
    const std::string del_list = in_clause(deleted, "did", del_params);
    db.execute(
        "DELETE FROM teller.\"transaction\" WHERE account_id = :account_id "
        "AND status = 'pending' AND transaction_id IN " + del_list,
        del_params);
    return deleted;
}

// #R001: Traceability for function `prune_unreferenced_relations`.
void prune_unreferenced_relations(Db& db) {
    auto collect = [&](const std::string& sql, const std::string& col) {
        std::vector<std::string> ids;
        for (const auto& row : db.query(sql)) {
            if (auto v = row.get_int(col)) ids.push_back(std::to_string(*v));
        }
        return ids;
    };
    const auto orphan_links = collect(
        "SELECT transaction_links_id FROM teller.transaction_links WHERE NOT EXISTS ("
        "SELECT 1 FROM teller.\"transaction\" t "
        "WHERE t.transaction_links_id = teller.transaction_links.transaction_links_id)",
        "transaction_links_id");
    const auto orphan_details = collect(
        "SELECT transaction_details_id FROM teller.transaction_details WHERE NOT EXISTS ("
        "SELECT 1 FROM teller.\"transaction\" t "
        "WHERE t.transaction_details_id = teller.transaction_details.transaction_details_id)",
        "transaction_details_id");
    const auto orphan_counterparties = collect(
        "SELECT transaction_details_counterparty_id FROM teller.transaction_details_counterparty "
        "WHERE NOT EXISTS (SELECT 1 FROM teller.transaction_details td "
        "WHERE td.transaction_details_counterparty_id = "
        "teller.transaction_details_counterparty.transaction_details_counterparty_id)",
        "transaction_details_counterparty_id");
    if (!orphan_links.empty()) {
        Params p;
        const std::string list = in_clause(orphan_links, "lid", p);
        db.execute("DELETE FROM teller.transaction_links WHERE transaction_links_id IN " + list, p);
    }
    if (!orphan_details.empty()) {
        Params p;
        const std::string list = in_clause(orphan_details, "tdid", p);
        db.execute("DELETE FROM teller.transaction_details WHERE transaction_details_id IN " + list,
                   p);
    }
    if (!orphan_counterparties.empty()) {
        Params p;
        const std::string list = in_clause(orphan_counterparties, "cpid", p);
        db.execute("DELETE FROM teller.transaction_details_counterparty "
                   "WHERE transaction_details_counterparty_id IN " + list,
                   p);
    }
}

// #R001: Traceability for function `upsert_account_balances_links`.
int64_t upsert_account_balances_links(Db& db, const json& links, std::optional<int64_t> existing_id) {
    const std::string self_link = opt_str(links, "self");
    const std::string account_link = opt_str(links, "account");
    if (existing_id) {
        db.execute(
            "UPDATE teller.account_balances_links SET self_link = :self_link, "
            "account_link = :account_link WHERE account_balances_links_id = :id",
            {{"self_link", self_link}, {"account_link", account_link}, {"id", *existing_id}});
        return *existing_id;
    }
    auto found = scalar_int(
        db,
        "SELECT account_balances_links_id FROM teller.account_balances_links WHERE self_link = :sl",
        {{"sl", self_link}}, "account_balances_links_id");
    if (found) return *found;
    return insert_returning_id(
        db,
        "INSERT INTO teller.account_balances_links (self_link, account_link) "
        "VALUES (:self_link, :account_link) "
        "ON CONFLICT (self_link) DO UPDATE SET account_link = EXCLUDED.account_link",
        "account_balances_links_id", {{"self_link", self_link}, {"account_link", account_link}});
}

// #R001: Traceability for function `upsert_account_balances`.
void upsert_account_balances(Db& db, const std::string& account_id, const json& bal) {
    auto existing = db.query_one(
        "SELECT account_balances_id, account_balances_links_id FROM teller.account_balances "
        "WHERE account_id = :id",
        {{"id", account_id}});
    std::optional<int64_t> existing_links =
        existing ? existing->get_int("account_balances_links_id") : std::nullopt;
    const int64_t links_id = upsert_account_balances_links(db, bal.at("links"), existing_links);
    Params vals{{"account_id", account_id},
                {"ledger", money_value(db, bal, "ledger")},
                {"available", money_value(db, bal, "available")},
                {"account_balances_links_id", links_id}};
    if (existing) {
        db.execute(
            "UPDATE teller.account_balances SET ledger = :ledger, available = :available, "
            "account_balances_links_id = :account_balances_links_id, updated_at = CURRENT_TIMESTAMP "
            "WHERE account_id = :account_id",
            vals);
    } else {
        db.execute(
            "INSERT INTO teller.account_balances (account_id, ledger, available, "
            "account_balances_links_id) "
            "VALUES (:account_id, :ledger, :available, :account_balances_links_id)",
            vals);
    }
}

} // namespace

// #R001: Traceability for function `money_to_cents`.
int64_t money_to_cents(const std::string& value) {
    std::string s;
    for (char c : value) {
        if (c != ' ' && c != '\t' && c != '\r' && c != '\n') s += c;
    }
    if (s.empty()) return 0;
    bool negative = false;
    size_t i = 0;
    if (s[0] == '+' || s[0] == '-') {
        negative = s[0] == '-';
        i = 1;
    }
    std::string int_part;
    std::string frac_part;
    bool in_frac = false;
    for (; i < s.size(); ++i) {
        const char c = s[i];
        if (c == '.') {
            in_frac = true;
            continue;
        }
        if (c < '0' || c > '9') throw ApiError(422, "invalid money value: " + value);
        (in_frac ? frac_part : int_part) += c;
    }
    while (frac_part.size() < 3) frac_part += '0';
    const int64_t whole = int_part.empty() ? 0 : std::stoll(int_part);
    const int64_t frac2 = std::stoll(frac_part.substr(0, 2));
    const bool round_up = frac_part[2] >= '5';
    int64_t cents = whole * 100 + frac2 + (round_up ? 1 : 0);
    return negative ? -cents : cents;
}

// #R001: Traceability for function `persist_all`.
void persist_all(db::Db& db, const json& raw_identities,
                 const json& raw_transactions_by_account, const json& raw_balances_by_account) {
    db::Transaction txn(db);
    try {
        for (const auto& item : raw_identities) {
            const json& account = item.at("account");
            upsert_account(db, account);
            for (const auto& owner : item.at("owners")) {
                const int64_t identity_id = upsert_identity(db, owner);
                upsert_account_identity(db, require_str(account, "id"), identity_id);
            }
        }
        if (raw_balances_by_account.is_object()) {
            for (auto it = raw_balances_by_account.begin(); it != raw_balances_by_account.end();
                 ++it) {
                upsert_account_balances(db, it.key(), it.value());
            }
        }
        if (raw_transactions_by_account.is_object()) {
            for (auto it = raw_transactions_by_account.begin();
                 it != raw_transactions_by_account.end(); ++it) {
                const std::vector<json> canonical = canonicalize_transactions(it.value());
                std::vector<std::string> fetched_ids;
                for (const auto& t : canonical) {
                    upsert_transaction(db, t);
                    fetched_ids.push_back(require_str(t, "id"));
                }
                if (!fetched_ids.empty()) {
                    reconcile_missing_pending(db, it.key(), fetched_ids);
                }
            }
        }
        prune_unreferenced_relations(db);
        txn.commit();
    } catch (...) {
        db.rollback();
        throw;
    }
}

// #R001: Traceability for function `plan_statement_transactions`.
std::vector<PlannedStatementTxn> plan_statement_transactions(
    db::Db& db, const std::string& account_id, const std::vector<statement::StatementTxn>& txns) {
    auto earliest_row = db.query_one(
        "SELECT MIN(date) AS min_date FROM teller.\"transaction\" "
        "WHERE account_id = :aid AND transaction_id LIKE 'txn_%'",
        {{"aid", account_id}});
    std::optional<std::string> earliest_api_date;
    if (earliest_row && !earliest_row->is_null("min_date")) {
        earliest_api_date = earliest_row->get_text("min_date");
    }
    std::map<std::tuple<std::string, std::string, std::string>, int> seen_occurrences;
    std::vector<PlannedStatementTxn> planned;
    planned.reserve(txns.size());
    for (const auto& txn : txns) {
        const auto key = std::make_tuple(txn.date, txn.amount, txn.description);
        const int occurrence = ++seen_occurrences[key];
        PlannedStatementTxn entry;
        entry.transaction_id =
            statement::make_txn_id(account_id, txn.date, txn.amount, txn.description, occurrence);
        entry.txn = txn;
        entry.occurrence = occurrence;
        // ISO date strings compare lexicographically in chronological order.
        entry.skipped_api_overlap = earliest_api_date && txn.date >= *earliest_api_date;
        planned.push_back(std::move(entry));
    }
    return planned;
}

// #R001: Traceability for function `upsert_statement_transactions`.
int upsert_statement_transactions(db::Db& db, const std::string& account_id,
                                  const std::vector<PlannedStatementTxn>& planned) {
    db::Transaction db_txn(db);
    int inserted = 0;
    try {
        for (const auto& entry : planned) {
            if (entry.skipped_api_overlap) continue;
            const json record = {
                {"id", entry.transaction_id},
                {"account_id", account_id},
                {"amount", entry.txn.amount},
                {"date", entry.txn.date},
                {"description", entry.txn.description},
                {"type", entry.txn.type},
                {"status", "posted"},
                {"running_balance", nullptr},
                {"details",
                 {{"processing_status", "complete"}, {"category", nullptr}, {"counterparty", nullptr}}},
                {"links",
                 {{"self", "stmt://" + entry.transaction_id},
                  {"account", "https://api.teller.io/accounts/" + account_id}}}};
            upsert_transaction(db, record);
            ++inserted;
        }
        db_txn.commit();
    } catch (...) {
        db.rollback();
        throw;
    }
    return inserted;
}

} // namespace tellercore::persist
// NOLINTEND(bugprone-easily-swappable-parameters)
