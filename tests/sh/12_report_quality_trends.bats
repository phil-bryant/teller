#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "12_report_quality_trends.sh"
  mkdir -p "${FIXTURE_ROOT}/artifacts/telemetry"
}

teardown() {
  teardown_shell_test
}

@test "fails when trend file is missing" {
  #R010-T01
  run bash "${FIXTURE_ROOT}/12_report_quality_trends.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing trend file"* ]]
}

@test "prints score and SLO summary from trend payload" {
  #R001-T01
  #R005-T01
  #R015-T01
  cat > "${FIXTURE_ROOT}/artifacts/telemetry/quality-trend.json" <<'JSON'
{"latest_run_started_at":"2026-05-26T00:00:00+00:00","latest_score":9.63,"rolling_21_runs":{"score_avg":9.42,"wall_p50_seconds":128.2,"wall_p95_seconds":149.8},"rolling_14d":{"score_avg":9.5,"pass_reliability":0.97},"performance_slo":{"warn":false,"fail":false}}
JSON
  cat > "${FIXTURE_ROOT}/artifacts/telemetry/quality-history.ndjson" <<'NDJSON'
{"score":9.63}
NDJSON
  run bash "${FIXTURE_ROOT}/12_report_quality_trends.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"latest score: 9.630 / 10.0"* ]]
  [[ "$output" == *"rolling20 wall p95: 149.80s"* ]]
  [[ "$output" == *"status: PASS"* ]]
}
