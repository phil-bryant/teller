#!/usr/bin/env bats

# Requirement test-case tags for requirements/19_fetch_teller_api_data-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  teardown_shell_test
}

@test "enrollment context builder discovers and filters contexts" {
  #R020
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_19_fetch_teller_api_data.EnrollmentContextDiscoveryTests.test_build_contexts_filters_by_institution \
    tests.py.test_19_fetch_teller_api_data.EnrollmentContextDiscoveryTests.test_build_contexts_uses_suffix_tokens_without_default_token
  [ "$status" -eq 0 ]
}

@test "dedupe logic keeps latest enrollment token variant" {
  #R020
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_19_fetch_teller_api_data.EnrollmentContextDiscoveryTests.test_dedupe_contexts_prefers_last_duplicate_entry
  [ "$status" -eq 0 ]
}

@test "api client forwards timeout and paginates with from_id" {
  #R005
  #R015
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_19_fetch_teller_api_data.TellerApiClientRequestTimeoutTests.test_get_passes_explicit_timeout_to_requests \
    tests.py.test_19_fetch_teller_api_data.TellerApiClientRequestTimeoutTests.test_fetch_all_transactions_uses_from_id_pagination
  [ "$status" -eq 0 ]
}
