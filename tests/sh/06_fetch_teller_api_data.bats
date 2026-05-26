#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  teardown_shell_test
}

@test "enrollment context builder discovers and filters contexts" {
  #R001-T01 #R001-T02 #R010-T01 #R010-T02 #R020-T01 #R020-T02 #R020-T03 #R025-T01 #R025-T02 #R030-T01 #R030-T02 #R035-T01
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_06_fetch_teller_api_data.EnrollmentContextDiscoveryTests.test_build_contexts_filters_by_institution \
    tests.py.test_06_fetch_teller_api_data.EnrollmentContextDiscoveryTests.test_build_contexts_uses_suffix_tokens_without_default_token
  [ "$status" -eq 0 ]
}

@test "dedupe logic keeps latest enrollment token variant" {
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_06_fetch_teller_api_data.EnrollmentContextDiscoveryTests.test_dedupe_contexts_prefers_last_duplicate_entry
  [ "$status" -eq 0 ]
}

@test "api client forwards timeout and paginates with from_id" {
  #R005-T01 #R005-T02 #R005-T03 #R005-T04 #R015-T01 #R015-T02 #R035-T02
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_06_fetch_teller_api_data.TellerApiClientRequestTimeoutTests.test_get_passes_explicit_timeout_to_requests \
    tests.py.test_06_fetch_teller_api_data.TellerApiClientRequestTimeoutTests.test_fetch_all_transactions_uses_from_id_pagination
  [ "$status" -eq 0 ]
}
