from __future__ import annotations

from datetime import datetime, timezone
from typing import Dict
from unittest.mock import patch

from fastapi import HTTPException
from hypothesis import event
from hypothesis.stateful import RuleBasedStateMachine, initialize, invariant, rule
from hypothesis.strategies import booleans, integers, sampled_from, text

from teller.teller_classification_api import _deactivate_match, _transition_match_state


_MATCH_STATES = (
    "ai_no_match_found",
    "ai_candidate_uncertain",
    "ai_match_confident",
    "human_confirmed_ai_match",
    "human_overrode_ai_match",
)
_ACTORS = ("ai", "human")


class _Result:
    def __init__(self, row=None):
        self._row = row

    def mappings(self):
        return self

    def fetchone(self):
        return self._row


class _FakeSession:
    def __init__(self, rows: Dict[int, Dict[str, object]]):
        self.rows = rows
        self.commits = 0
        self.rollbacks = 0
        self.audit_count = 0

    def execute(self, _statement, params=None):
        params = params or {}
        match_id = params.get("target_match_id")
        row = self.rows.get(match_id)
        if row is None:
            return _Result(row=None)

        if "to_state" in params:
            row["state"] = params["to_state"]
            row["selected_by"] = params["actor"]
            row["updated_at"] = datetime.now(timezone.utc)
            if "email_message_id" in params:
                row["email_message_id"] = params["email_message_id"]
            elif row.get("email_message_id") is not None and params.get("to_state") == "ai_no_match_found":
                row["email_message_id"] = None
            return _Result(
                row={
                    "transaction_id": row["transaction_id"],
                    "state": row["state"],
                    "selected_by": row["selected_by"],
                    "updated_at": row["updated_at"],
                }
            )

        if row.get("active") is not True:
            return _Result(row=None)
        row["active"] = False
        row["updated_at"] = datetime.now(timezone.utc)
        return _Result(
            row={
                "transaction_id": row["transaction_id"],
                "state": row["state"],
                "selected_by": row["selected_by"],
                "updated_at": row["updated_at"],
            }
        )

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


class MatchLifecycleStateMachine(RuleBasedStateMachine):
    def __init__(self):
        super().__init__()
        self.session = _FakeSession({})

    @initialize(match_count=integers(min_value=1, max_value=4))
    def seed_rows(self, match_count):
        self.session.rows = {
            idx: {
                "transaction_id": f"txn_{idx}",
                "state": "ai_match_confident",
                "selected_by": "ai",
                "updated_at": datetime.now(timezone.utc),
                "active": True,
                "email_message_id": f"msg_{idx}",
            }
            for idx in range(1, match_count + 1)
        }

    @rule(
        match_id=integers(min_value=1, max_value=4),
        to_state=sampled_from(_MATCH_STATES),
        actor=sampled_from(_ACTORS),
        clear_email=booleans(),
        note=text(min_size=0, max_size=80),
    )
    def transition_state(self, match_id, to_state, actor, clear_email, note):
        event(f"transition_attempt:{to_state}:{actor}")
        if match_id not in self.session.rows:
            event("transition_missing_row")
            return

        def read_match_row(_session, requested_match_id):
            row = self.session.rows.get(requested_match_id)
            if row is None:
                raise HTTPException(status_code=404, detail=f"Unknown match_id: {requested_match_id}")
            return {
                "state": row["state"],
                "transaction_id": row["transaction_id"],
                "selected_by": row["selected_by"],
            }

        def insert_match_audit(*_args, **_kwargs):
            self.session.audit_count += 1

        with patch("teller.teller_classification_api._read_match_row", side_effect=read_match_row), patch(
            "teller.teller_classification_api._insert_match_audit", side_effect=insert_match_audit
        ):
            previous_state = self.session.rows[match_id]["state"]
            response = _transition_match_state(
                session=self.session,
                match_id=match_id,
                to_state=to_state,
                actor=actor,
                note=note,
                clear_email_message_id=clear_email,
            )

        row = self.session.rows[match_id]
        assert response.state == row["state"] == to_state
        assert response.selected_by == actor
        event(f"transition_edge:{previous_state}->{response.state}:{response.selected_by}")

    @rule(match_id=integers(min_value=1, max_value=4), note=text(min_size=0, max_size=80))
    def deactivate_state(self, match_id, note):
        event("deactivate_attempt")
        if match_id not in self.session.rows:
            event("deactivate_missing_row")
            return
        if self.session.rows[match_id].get("active") is not True:
            event("deactivate_inactive_row")
            return

        def read_active_row(_session, requested_match_id):
            row = self.session.rows.get(requested_match_id)
            if row is None or row.get("active") is not True:
                raise HTTPException(status_code=404, detail=f"Unknown match_id: {requested_match_id}")
            return {
                "state": row["state"],
                "transaction_id": row["transaction_id"],
                "selected_by": row["selected_by"],
            }

        def insert_match_audit(*_args, **_kwargs):
            self.session.audit_count += 1

        with patch("teller.teller_classification_api._read_active_match_row", side_effect=read_active_row), patch(
            "teller.teller_classification_api._insert_match_audit", side_effect=insert_match_audit
        ):
            response = _deactivate_match(self.session, match_id, note)

        assert response.match_id == match_id
        assert self.session.rows[match_id]["active"] is False
        event("deactivate_success")

    @invariant()
    def audit_count_never_exceeds_commits(self):
        assert self.session.audit_count <= self.session.commits

class TestMatchLifecycleStateMachine(MatchLifecycleStateMachine.TestCase):
    pass
