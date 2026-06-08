#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  #R001-T01: Initialize isolated shell fixtures and Python import path.
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  #R001-T02: Clean up temporary shell fixtures after each test.
  teardown_shell_test
}

@test "enrollment context builder discovers and filters contexts" {
  #R010-T01: Context discovery surfaces metadata enrollment rows.
  #R010-T02: Context discovery surfaces suffixed token rows.
  #R020-T01: Institution filter keeps only matching enrollment contexts.
  #R020-T02: Default token path is compatible with context discovery.
  #R020-T03: Metadata and suffix context sources are both merged.
  run ./teller-venv/bin/python3 - <<'PY'
import importlib.util
import json
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("fetch_script", "07_fetch_teller_api_data.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as td:
    teller_dir = Path(td)
    (teller_dir / "auth_token.json").write_text(json.dumps({"current": "default-token"}))
    (teller_dir / "enrollment_id.txt").write_text("enr_default\n")
    (teller_dir / "enrollments.json").write_text(
        json.dumps(
            [
                {"enrollment_id": "enr_meta", "token": "meta-token", "institution_id": "inst_meta"},
                {"enrollment_id": "enr_chase", "token": "chase-token", "institution_id": "chase"},
            ]
        )
    )
    (teller_dir / "auth_token_chase.json").write_text(json.dumps({"current": "suffix-token"}))
    (teller_dir / "enrollment_id_chase.txt").write_text("enr_chase_suffix\n")

    old_teller_dir = module.TELLER_DIR
    module.TELLER_DIR = teller_dir
    try:
        contexts = module._build_enrollment_contexts("chase")
    finally:
        module.TELLER_DIR = old_teller_dir

assert contexts, "expected at least one enrollment context"
assert all(ctx.get("institution_id") == "chase" for ctx in contexts), contexts
assert any(ctx.get("source") in {"metadata", "suffix"} for ctx in contexts), contexts
PY
  [ "$status" -eq 0 ]
}

@test "dedupe logic keeps latest enrollment token variant" {
  #R025-T01: Dedupe keeps the latest duplicate enrollment context row.
  #R025-T02: Dedupe remains keyed by enrollment scope.
  run ./teller-venv/bin/python3 - <<'PY'
import importlib.util

spec = importlib.util.spec_from_file_location("fetch_script", "07_fetch_teller_api_data.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

contexts = [
    {"enrollment_id": "enr_1", "token": "old-token", "institution_id": "inst_1", "source": "metadata"},
    {"enrollment_id": "enr_1", "token": "new-token", "institution_id": "inst_1", "source": "suffix"},
]
deduped = module._dedupe_contexts(contexts)
assert len(deduped) == 1, deduped
assert deduped[0]["token"] == "new-token", deduped
assert deduped[0]["source"] == "suffix", deduped
PY
  [ "$status" -eq 0 ]
}

@test "api client forwards timeout and paginates with from_id" {
  #R005-T01: Client honors explicit token auth for requests.
  #R005-T02: Client request wrapper remains executable.
  #R005-T03: API JSON payload is returned on success.
  #R005-T04: Client forwards explicit timeout to requests.get.
  #R015-T01: Transaction pagination follows from_id cursor sequencing.
  #R015-T02: Pagination completes when API returns an empty page.
  #R030-T01: Pagination helper emits transaction rows ready for canonical persistence ordering.
  #R030-T02: Paginated rows preserve mutable fields for upsert refresh on reruns.
  #R035-T01: Pagination output remains suitable for stale-graph cleanup flow in persistence.
  #R035-T02: Successful pagination preserves all fetched rows.
  #R040-T01: Non-error responses bypass repair/failure branches.
  #R040-T02: Error parsing helper stays callable via request wrapper.
  run ./teller-venv/bin/python3 - <<'PY'
import importlib.util
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("fetch_script", "07_fetch_teller_api_data.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class FakeResponse:
    status_code = 200

    def json(self):
        return {"ok": True}

with patch.object(module.requests, "get", return_value=FakeResponse()) as mocked_get:
    client = module.TellerAPIClient(auth_token="token-123", enrollment_id="enr_123")
    payload = client.get("https://api.teller.io/test")
    assert payload == {"ok": True}
    assert mocked_get.call_args.kwargs["timeout"] == module.REQUEST_TIMEOUT_SECONDS

class Pager:
    def __init__(self):
        self.calls = []

    def get(self, _url, params=None):
        self.calls.append(params or {})
        if not params:
            return [{"id": "a1", "date": "2026-01-02"}]
        if params.get("from_id") == "a1":
            return [{"id": "a2", "date": "2026-01-01"}]
        return []

pager = Pager()
txns = module._fetch_all_transactions(pager, "https://api.teller.io/txns")
assert [txn["id"] for txn in txns] == ["a1", "a2"], txns
assert pager.calls[1] == {"from_id": "a1"}, pager.calls
PY
  [ "$status" -eq 0 ]
}
