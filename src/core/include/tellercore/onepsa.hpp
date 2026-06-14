// #R001: Module-level traceability anchor.
#pragma once

#include <map>
#include <string>
#include <vector>

namespace tellercore::onepsa {

// Reads fields from a 1psa item via libonepsa (dlopen of ONEPSA_LIB_PATH,
// default /usr/local/lib/libonepsa.dylib). Mirrors teller_db_profile.py:
// returns an empty map when the library cannot be loaded, and stops after the
// first per-field error so callers can fall back to ~/.env immediately.
std::map<std::string, std::string> read_fields(const std::string& item,
                                               const std::vector<std::string>& fields);

// Single-field convenience; empty string when missing/unavailable.
std::string read_field(const std::string& item, const std::string& field);

// Strict password lookup mirroring teller_db._read_password_from_onepsa:
// throws std::runtime_error on library/lookup failure so the caller can log
// and fall back to ~/.env.
std::string read_password_strict(const std::string& item);

} // namespace tellercore::onepsa
