#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "13_validate_quality_target.sh"
  mkdir -p "${FIXTURE_ROOT}/artifacts/telemetry"
}

teardown() {
  teardown_shell_test
}

@test "fails when history file is missing" {
  #R010-T01
  run bash "${FIXTURE_ROOT}/13_validate_quality_target.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing quality history"* ]]
}

@test "fails when recent history is insufficient" {
  #R015-T01
  cat > "${FIXTURE_ROOT}/artifacts/telemetry/quality-history.ndjson" <<'NDJSON'
{"run_started_at":"2026-05-19T12:00:00+00:00","score":9.7,"components":{"lane_reliability":0.97}}
NDJSON
  run bash "${FIXTURE_ROOT}/13_validate_quality_target.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"insufficient history"* ]]
}

@test "passes when two consecutive weeks meet score and reliability targets" {
  #R001-T01
  #R005-T01
  #R020-T01
  python3 - <<'PY' > "${FIXTURE_ROOT}/artifacts/telemetry/quality-history.ndjson"
import json
from datetime import datetime, timedelta, timezone

now = datetime.now(timezone.utc)
week_start = now - timedelta(days=now.weekday())
current_week = week_start.replace(hour=12, minute=0, second=0, microsecond=0)
previous_week = current_week - timedelta(days=7)

for ts, score, reliability in (
    (previous_week, 9.6, 0.98),
    (current_week, 9.7, 0.97),
):
    print(
        json.dumps(
            {
                "run_started_at": ts.isoformat(),
                "score": score,
                "components": {"lane_reliability": reliability},
            },
            separators=(",", ":"),
        )
    )
PY
  run bash "${FIXTURE_ROOT}/13_validate_quality_target.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"quality target validated"* ]]
}
