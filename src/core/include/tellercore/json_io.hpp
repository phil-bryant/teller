#pragma once

#include <optional>
#include <string>

#include <nlohmann/json.hpp>

#include "tellercore/db.hpp"

namespace tellercore::json_io {

using nlohmann::json;

// Backend Value -> JSON (null/int/real/text).
json value_to_json(const db::Value& value);
json row_to_json(const db::Row& row);

// "YYYY-MM-DD HH:MM:SS" (SQLite CURRENT_TIMESTAMP, UTC) -> "YYYY-MM-DDTHH:MM:SSZ".
// Already-ISO strings pass through with a Z suffix when no offset is present.
std::string to_utc_iso8601(const std::string& sqlite_timestamp);

// Current wall time as "YYYY-MM-DDTHH:MM:SS.ffffffZ"-style UTC ISO string.
std::string now_utc_iso8601();

std::optional<std::string> opt_text(const json& j, const std::string& key);

} // namespace tellercore::json_io
