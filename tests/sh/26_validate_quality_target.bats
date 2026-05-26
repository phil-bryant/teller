#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "26_validate_quality_target.sh"
  mkdir -p "${FIXTURE_ROOT}/artifacts/telemetry"
}

teardown() {
  teardown_shell_test
}

@test "fails when history file is missing" {
  run bash "${FIXTURE_ROOT}/26_validate_quality_target.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing quality history"* ]]
}

@test "passes when two consecutive weeks meet score and reliability targets" {
  cat > "${FIXTURE_ROOT}/artifacts/telemetry/quality-history.ndjson" <<'NDJSON'
{"run_started_at":"2026-05-11T12:00:00+00:00","score":9.6,"components":{"lane_reliability":0.98}}
{"run_started_at":"2026-05-19T12:00:00+00:00","score":9.7,"components":{"lane_reliability":0.97}}
NDJSON
  run bash "${FIXTURE_ROOT}/26_validate_quality_target.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"quality target validated"* ]]
}
