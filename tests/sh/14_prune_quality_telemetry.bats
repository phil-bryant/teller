#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "14_prune_quality_telemetry.sh"
}

teardown() {
  teardown_shell_test
}

@test "prunes oldest lane summaries and keeps newest by count" {
  #R001-T01 #R001 #R005-T01 #R005 #R010-T01 #R010
  local telemetry_dir="${FIXTURE_ROOT}/artifacts/telemetry"
  mkdir -p "${telemetry_dir}"
  mkdir -p "${FIXTURE_ROOT}/tmp-run"

  touch "${telemetry_dir}/lane-summary-20260101T000000Z.json"
  touch "${telemetry_dir}/lane-summary-20260102T000000Z.json"
  touch "${telemetry_dir}/lane-summary-20260103T000000Z.json"
  touch "${telemetry_dir}/lane-summary-20260104T000000Z.json"

  run bash -c "cd '${FIXTURE_ROOT}/tmp-run' && env QUALITY_LANE_SUMMARY_KEEP=2 bash '${FIXTURE_ROOT}/14_prune_quality_telemetry.sh'"

  [ "$status" -eq 0 ]
  [[ "$output" == *"removed=2, kept=2"* ]]
  [ ! -f "${telemetry_dir}/lane-summary-20260101T000000Z.json" ]
  [ ! -f "${telemetry_dir}/lane-summary-20260102T000000Z.json" ]
  [ -f "${telemetry_dir}/lane-summary-20260103T000000Z.json" ]
  [ -f "${telemetry_dir}/lane-summary-20260104T000000Z.json" ]
}

@test "succeeds without changes when lane summaries are absent" {
  #R010
  local telemetry_dir="${FIXTURE_ROOT}/artifacts/telemetry"
  mkdir -p "${telemetry_dir}"
  touch "${telemetry_dir}/quality-history.ndjson"

  run env QUALITY_TELEMETRY_DIR="${telemetry_dir}" \
    bash "${FIXTURE_ROOT}/14_prune_quality_telemetry.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"No lane summary files found"* ]]
  [ -f "${telemetry_dir}/quality-history.ndjson" ]
}

@test "fails when QUALITY_LANE_SUMMARY_KEEP is not a non-negative integer" {
  #R010-T02 #R010
  local telemetry_dir="${FIXTURE_ROOT}/artifacts/telemetry"
  mkdir -p "${telemetry_dir}"
  touch "${telemetry_dir}/lane-summary-20260101T000000Z.json"

  run env QUALITY_TELEMETRY_DIR="${telemetry_dir}" \
    QUALITY_LANE_SUMMARY_KEEP=abc \
    bash "${FIXTURE_ROOT}/14_prune_quality_telemetry.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a non-negative integer"* ]]
}
