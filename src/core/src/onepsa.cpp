#include "tellercore/onepsa.hpp"

#include <dlfcn.h>

#include <cstdlib>
#include <stdexcept>

namespace tellercore::onepsa {

namespace {

using GetFieldFn = void* (*)(const char*, const char*, char**);
using StringFreeFn = void (*)(void*);

struct Lib {
    void* handle = nullptr;
    GetFieldFn get_field = nullptr;
    StringFreeFn string_free = nullptr;
    bool ok() const { return handle != nullptr && get_field != nullptr && string_free != nullptr; }
};

Lib load_lib() {
    Lib lib;
    const char* env_path = std::getenv("ONEPSA_LIB_PATH");
    const std::string path = env_path != nullptr && env_path[0] != '\0'
                                 ? env_path
                                 : "/usr/local/lib/libonepsa.dylib";
    lib.handle = dlopen(path.c_str(), RTLD_LAZY | RTLD_LOCAL);
    if (lib.handle == nullptr) return lib;
    lib.get_field = reinterpret_cast<GetFieldFn>(dlsym(lib.handle, "OnepsaGetField"));
    lib.string_free = reinterpret_cast<StringFreeFn>(dlsym(lib.handle, "OnepsaStringFree"));
    return lib;
}

} // namespace

std::map<std::string, std::string> read_fields(const std::string& item,
                                               const std::vector<std::string>& fields) {
    std::map<std::string, std::string> parsed;
    const Lib lib = load_lib();
    if (!lib.ok()) return parsed;
    for (const auto& field : fields) {
        char* err = nullptr;
        void* out_ptr = lib.get_field(item.c_str(), field.c_str(), &err);
        if (err != nullptr) {
            lib.string_free(err);
            // Stop after the first libonepsa error so callers can immediately
            // fall back to ~/.env (Python parity).
            break;
        }
        if (out_ptr == nullptr) continue;
        std::string value(static_cast<const char*>(out_ptr));
        lib.string_free(out_ptr);
        // Trim whitespace.
        const auto begin = value.find_first_not_of(" \t\r\n");
        const auto end = value.find_last_not_of(" \t\r\n");
        value = begin == std::string::npos ? "" : value.substr(begin, end - begin + 1);
        if (!value.empty()) parsed[field] = value;
    }
    return parsed;
}

std::string read_field(const std::string& item, const std::string& field) {
    const auto fields = read_fields(item, {field});
    auto it = fields.find(field);
    return it == fields.end() ? std::string() : it->second;
}

std::string read_password_strict(const std::string& item) {
    const Lib lib = load_lib();
    if (!lib.ok()) throw std::runtime_error("libonepsa could not be loaded");
    char* err = nullptr;
    void* out_ptr = lib.get_field(item.c_str(), "password", &err);
    if (err != nullptr) {
        std::string message(err);
        lib.string_free(err);
        throw std::runtime_error(message);
    }
    if (out_ptr == nullptr) throw std::runtime_error("libonepsa returned null password without error");
    std::string value(static_cast<const char*>(out_ptr));
    lib.string_free(out_ptr);
    const auto begin = value.find_first_not_of(" \t\r\n");
    const auto end = value.find_last_not_of(" \t\r\n");
    return begin == std::string::npos ? "" : value.substr(begin, end - begin + 1);
}

} // namespace tellercore::onepsa
