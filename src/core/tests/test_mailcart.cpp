#include <catch2/catch_test_macros.hpp>

#include "tellercore/mailcart.hpp"

using namespace tellercore::mailcart;

TEST_CASE("validated_https_base_url accepts https URLs", "[mailcart]") {
    CHECK(validated_https_base_url("https://127.0.0.1:8788") == "https://127.0.0.1:8788");
    // Parity with _validated_https_base_url: only whitespace is trimmed; the
    // trailing slash is stripped later by the client constructor.
    CHECK(validated_https_base_url("https://127.0.0.1:8788/") == "https://127.0.0.1:8788/");
    CHECK(validated_https_base_url("  https://host.local  ") == "https://host.local");
}

TEST_CASE("validated_https_base_url rejects non-https and empty configuration", "[mailcart]") {
    auto throws_503 = [](const std::string& url) {
        try {
            validated_https_base_url(url);
        } catch (const MailcartError& exc) {
            return exc.status_code == 503;
        }
        return false;
    };
    CHECK(throws_503("http://127.0.0.1:8788"));
    CHECK(throws_503(""));
    CHECK(throws_503("https://"));
}
