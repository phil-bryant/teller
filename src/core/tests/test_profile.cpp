// NOLINTBEGIN(concurrency-mt-unsafe,bugprone-throwing-static-initialization,cert-err58-cpp)
#include <catch2/catch_test_macros.hpp>

#include <cstdlib>

#include "tellercore/profile.hpp"

using namespace tellercore;

namespace {

// RAII env var override that restores the prior value on scope exit.
struct ScopedEnv {
    // #R001: Traceability for function `ScopedEnv`.
    ScopedEnv(const char* name, const char* value) : name_(name) {
        const char* prior = std::getenv(name);
        had_prior_ = prior != nullptr;
        if (had_prior_) prior_ = prior;
        if (value) {
            setenv(name, value, 1);
        } else {
            unsetenv(name);
        }
    }
    // #R001: Traceability for function `ScopedEnv`.
    ~ScopedEnv() {
        if (had_prior_) {
            setenv(name_.c_str(), prior_.c_str(), 1);
        } else {
            unsetenv(name_.c_str());
        }
    }
    std::string name_;
    std::string prior_;
    bool had_prior_ = false;
};

} // namespace

TEST_CASE("TELLER_DB_SQLITE_PATH env forces the sqlite target", "[profile]") {
    ScopedEnv path("TELLER_DB_SQLITE_PATH", "/tmp/teller-profile-test.sqlite3");
    ScopedEnv key("TELLER_DB_SQLCIPHER_KEY", "secret-key");

    const DbProfile p = resolve_profile();
    CHECK(p.target == DbTarget::kSqlite);
    CHECK(p.name == "sqlite");
    CHECK(p.sqlite_path == "/tmp/teller-profile-test.sqlite3");
    CHECK(p.sqlcipher_key == "secret-key");

    const SqliteProfile sp = resolve_sqlite_profile();
    CHECK(sp.sqlite_path == "/tmp/teller-profile-test.sqlite3");
    CHECK(sp.sqlcipher_key == "secret-key");
}
// NOLINTEND(concurrency-mt-unsafe,bugprone-throwing-static-initialization,cert-err58-cpp)
