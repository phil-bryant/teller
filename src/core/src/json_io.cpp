#include "tellercore/json_io.hpp"

#include <chrono>
#include <cstdio>
#include <ctime>

namespace tellercore::json_io {

json value_to_json(const db::Value& value) {
    if (std::holds_alternative<std::monostate>(value)) return nullptr;
    if (std::holds_alternative<int64_t>(value)) return std::get<int64_t>(value);
    if (std::holds_alternative<double>(value)) return std::get<double>(value);
    return std::get<std::string>(value);
}

json row_to_json(const db::Row& row) {
    json out = json::object();
    for (const auto& [name, value] : row.columns) out[name] = value_to_json(value);
    return out;
}

std::string to_utc_iso8601(const std::string& sqlite_timestamp) {
    std::string out = sqlite_timestamp;
    if (out.size() >= 11 && out[10] == ' ') out[10] = 'T';
    const bool has_offset = out.find('Z') != std::string::npos ||
                            out.find('+', 10) != std::string::npos ||
                            (out.size() > 19 && out.rfind('-') > 10 && out.rfind('-') >= 19);
    if (!has_offset) out += "Z";
    return out;
}

std::string now_utc_iso8601() {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto secs = time_point_cast<seconds>(now);
    const auto micros = duration_cast<microseconds>(now - secs).count();
    const std::time_t t = system_clock::to_time_t(secs);
    std::tm tm_utc{};
    gmtime_r(&t, &tm_utc);
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d.%06lldZ",
                  tm_utc.tm_year + 1900, tm_utc.tm_mon + 1, tm_utc.tm_mday,
                  tm_utc.tm_hour, tm_utc.tm_min, tm_utc.tm_sec,
                  static_cast<long long>(micros));
    return buf;
}

std::optional<std::string> opt_text(const json& j, const std::string& key) {
    auto it = j.find(key);
    if (it == j.end() || it->is_null()) return std::nullopt;
    if (it->is_string()) return it->get<std::string>();
    return it->dump();
}

} // namespace tellercore::json_io
