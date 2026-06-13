#include <catch2/catch_test_macros.hpp>

#include "tellercore/persist.hpp"

using tellercore::persist::money_to_cents;

TEST_CASE("money_to_cents converts whole and fractional dollars", "[money]") {
    CHECK(money_to_cents("12.34") == 1234);
    CHECK(money_to_cents("56.00") == 5600);
    CHECK(money_to_cents("0") == 0);
    CHECK(money_to_cents("9") == 900);
    CHECK(money_to_cents("100") == 10000);
}

TEST_CASE("money_to_cents rounds half up at the cent", "[money]") {
    CHECK(money_to_cents("0.125") == 13);   // half rounds up
    CHECK(money_to_cents("0.124") == 12);   // below half rounds down
    CHECK(money_to_cents("0.1249") == 12);
    CHECK(money_to_cents("0.995") == 100);  // carry propagates
    CHECK(money_to_cents("1.005") == 101);
}

TEST_CASE("money_to_cents preserves sign", "[money]") {
    CHECK(money_to_cents("-12.34") == -1234);
    CHECK(money_to_cents("-0.01") == -1);
    CHECK(money_to_cents("+7.50") == 750);
}
