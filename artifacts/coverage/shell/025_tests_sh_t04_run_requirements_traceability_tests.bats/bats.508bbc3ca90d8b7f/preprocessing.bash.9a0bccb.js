var data = {lines:[
{"lineNum":"    1","line":"#!/usr/bin/env bash"},
{"lineNum":"    2","line":""},
{"lineNum":"    3","line":"bats_export_preprocess_source_BATS_TEST_SOURCE() {","class":"lineNoCov","hits":"0","possible_hits":"0",},
{"lineNum":"    4","line":"  # export to make it visible to bats_evaluate_preprocessed_source"},
{"lineNum":"    5","line":"  # since the latter runs in bats-exec-test\'s bash while this runs in bats-exec-file\'s"},
{"lineNum":"    6","line":"  export BATS_TEST_SOURCE=\"$BATS_RUN_TMPDIR/${BATS_TEST_FILE_NUMBER?}-${BATS_TEST_FILENAME##*/}.src\"","class":"lineCov","hits":"4","order":"181","possible_hits":"0",},
{"lineNum":"    7","line":"}"},
{"lineNum":"    8","line":""},
{"lineNum":"    9","line":"bats_preprocess_source() { # index","class":"lineNoCov","hits":"0","possible_hits":"0",},
{"lineNum":"   10","line":"  bats_export_preprocess_source_BATS_TEST_SOURCE","class":"lineCov","hits":"1","order":"180","possible_hits":"0",},
{"lineNum":"   11","line":"  # shellcheck disable=SC2153"},
{"lineNum":"   12","line":"  CHECK_BATS_COMMENT_COMMANDS=1 \"$BATS_ROOT/libexec/bats-core/bats-preprocess\" \"$BATS_TEST_FILENAME\" >\"$BATS_TEST_SOURCE\"","class":"lineCov","hits":"2","order":"182","possible_hits":"0",},
{"lineNum":"   13","line":"}"},
{"lineNum":"   14","line":""},
{"lineNum":"   15","line":"bats_evaluate_preprocessed_source() {","class":"lineNoCov","hits":"0","possible_hits":"0",},
{"lineNum":"   16","line":"  # Dynamically loaded user files provided outside of Bats."},
{"lineNum":"   17","line":"  # shellcheck disable=SC1090"},
{"lineNum":"   18","line":"  source \"${BATS_TEST_SOURCE?}\"","class":"lineCov","hits":"4","order":"502","possible_hits":"0",},
{"lineNum":"   19","line":"}"},
]};
var percent_low = 25;var percent_high = 75;
var header = { "command" : "bats", "date" : "2026-06-07 13:57:48", "instrumented" : 7, "covered" : 4,};
var merged_data = [];
