from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Optional

from fastapi import HTTPException
from sqlalchemy import String, bindparam, cast, func, text, update
from sqlalchemy.exc import DataError, IntegrityError

from teller.classification.constants import (
    _CATEGORY_TEXT_FIELDS,
    _EXISTENCE_QUERIES,
    _LATEST_MATCH_RUN_SQL,
    _MATCH_REVIEW_TABLE,
    _MATCH_SELECTED_BY_ENUM,
    _MATCH_STATE_ENUM,
    _IS_SQLITE,
)
from teller.classification.schemas import (
    CategoryMutationBase,
    CategoryOption,
    ClassificationWriteResponse,
    MatchReviewActionResponse,
)
from teller.classification.text import _display_label, _normalize_text, _validate_email_message_id

if _IS_SQLITE:
    _INSERT_MATCH_AUDIT_SQL = text(
        """
        INSERT INTO teller.transaction_email_match_audit (
            match_id,
            from_state,
            to_state,
            actor,
            note
        ) VALUES (
            :match_id,
            :from_state,
            :to_state,
            :actor,
            :note
        )
    """
    )
    _CREATE_MATCH_SQL = text(
        """
            INSERT INTO teller.transaction_email_match (
                transaction_id,
                email_message_id,
                state,
                ai_confidence,
                selected_by,
                active
            ) VALUES (
                :transaction_id,
                :email_message_id,
                :state,
                :ai_confidence,
                :selected_by,
                TRUE
            )
            RETURNING match_id, updated_at
        """
    )
else:
    _INSERT_MATCH_AUDIT_SQL = text(
        """
        INSERT INTO teller.transaction_email_match_audit (
            match_id,
            from_state,
            to_state,
            actor,
            note
        ) VALUES (
            :match_id,
            CAST(:from_state AS teller.transaction_email_match_state),
            CAST(:to_state AS teller.transaction_email_match_state),
            CAST(:actor AS teller.transaction_email_match_selected_by),
            :note
        )
    """
    )
    _CREATE_MATCH_SQL = text(
        """
            INSERT INTO teller.transaction_email_match (
                transaction_id,
                email_message_id,
                state,
                ai_confidence,
                selected_by,
                active
            ) VALUES (
                :transaction_id,
                :email_message_id,
                CAST(:state AS teller.transaction_email_match_state),
                :ai_confidence,
                CAST(:selected_by AS teller.transaction_email_match_selected_by),
                TRUE
            )
            RETURNING match_id, updated_at
        """
    )


def _estimate_transaction_total(*, offset: int, limit: int, row_count: int) -> int:
    if row_count < limit:
        return offset + row_count
    return offset + row_count + 1


def _match_review_filters(state: str, only_unmoved: bool):
    filters = [_MATCH_REVIEW_TABLE.c.active.is_(True)]
    if state:
        filters.append(cast(_MATCH_REVIEW_TABLE.c.state, String) == bindparam("state"))
    if only_unmoved:
        filters.append(_MATCH_REVIEW_TABLE.c.moved_to_matchy_at.is_(None))
    return filters


def _ensure_exists(session, table: str, column: str, value: object, error: str):
    query = _EXISTENCE_QUERIES.get((table, column))
    if query is None:
        raise HTTPException(status_code=500, detail=f"Unsupported existence check for {table}.{column}")
    row = session.execute(query, {"value": value}).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=error)


def _category_params(body: CategoryMutationBase, *, include_unset: bool) -> Dict[str, Optional[str]]:
    fields = _CATEGORY_TEXT_FIELDS if include_unset else sorted(body.model_fields_set.intersection(_CATEGORY_TEXT_FIELDS))
    return {field_name: _normalize_text(getattr(body, field_name)) for field_name in fields}


def _fetch_category(session, category_id: int) -> Dict[str, object]:
    row = session.execute(
        text(
            """
        SELECT nys_snw_category_id, level_1, level_1_name, level_2, level_2_name, level_3, level_4,
               categorization, applicability, is_seed
          FROM teller.nys_snw_category
         WHERE nys_snw_category_id = :nys_snw_category_id
         LIMIT 1
    """
        ),
        {"nys_snw_category_id": category_id},
    ).mappings().fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"Unknown nys_snw_category_id: {category_id}")
    return dict(row)


def _category_option_from_row(row: Dict[str, object]) -> CategoryOption:
    category_data = {
        "nys_snw_category_id": row["nys_snw_category_id"],
        "level_1": row.get("level_1"),
        "level_1_name": row.get("level_1_name"),
        "level_2": row.get("level_2"),
        "level_2_name": row.get("level_2_name"),
        "level_3": row.get("level_3"),
        "level_4": row.get("level_4"),
        "categorization": row.get("categorization"),
        "applicability": row.get("applicability"),
    }
    return CategoryOption(**category_data, display_label=_display_label(category_data))


def _normalized_category_fields(row: Dict[str, object]) -> Dict[str, Optional[str]]:
    return {
        "level_1": _normalize_text(row.get("level_1")),
        "level_1_name": _normalize_text(row.get("level_1_name")),
        "level_2": _normalize_text(row.get("level_2")),
        "level_2_name": _normalize_text(row.get("level_2_name")),
        "level_3": _normalize_text(row.get("level_3")),
        "level_4": _normalize_text(row.get("level_4")),
        "categorization": _normalize_text(row.get("categorization")),
        "applicability": _normalize_text(row.get("applicability")),
    }


def _create_category(session, body: CategoryMutationBase) -> CategoryOption:
    params = _category_params(body, include_unset=True)
    if all(value is None for value in params.values()):
        raise HTTPException(status_code=422, detail="Category create payload must include non-empty hierarchy text")
    created = session.execute(
        text(
            """
        INSERT INTO teller.nys_snw_category (
            level_1, level_1_name, level_2, level_2_name, level_3, level_4, categorization, applicability
        ) VALUES (
            :level_1, :level_1_name, :level_2, :level_2_name, :level_3, :level_4, :categorization, :applicability
        )
        RETURNING nys_snw_category_id
    """
        ),
        params,
    ).fetchone()
    session.commit()
    row = _fetch_category(session, created[0])
    return _category_option_from_row(row)


def _update_category(session, body: CategoryMutationBase, category_id: int) -> CategoryOption:
    _ensure_exists(session, "nys_snw_category", "nys_snw_category_id", category_id, f"Unknown nys_snw_category_id: {category_id}")
    existing = _fetch_category(session, category_id)
    if existing.get("is_seed"):
        raise HTTPException(status_code=409, detail=f"Category {category_id} is seed-protected and cannot be modified")
    patch_params = _category_params(body, include_unset=False)
    if not patch_params:
        raise HTTPException(status_code=422, detail="Category update payload must include at least one mutable field")
    merged_params = _normalized_category_fields(existing)
    merged_params.update(patch_params)
    if all(value is None for value in merged_params.values()):
        raise HTTPException(status_code=409, detail="Category mutation must include at least one non-empty hierarchy field")
    params = dict(merged_params)
    params["nys_snw_category_id"] = category_id
    session.execute(
        text(
            """
        UPDATE teller.nys_snw_category
           SET level_1 = :level_1,
               level_1_name = :level_1_name,
               level_2 = :level_2,
               level_2_name = :level_2_name,
               level_3 = :level_3,
               level_4 = :level_4,
               categorization = :categorization,
               applicability = :applicability,
               updated_at = CURRENT_TIMESTAMP
         WHERE nys_snw_category_id = :nys_snw_category_id
    """
        ),
        params,
    )
    session.commit()
    row = _fetch_category(session, category_id)
    return _category_option_from_row(row)


def _write_category(session, body: CategoryMutationBase, category_id: Optional[int] = None) -> CategoryOption:
    try:
        if category_id is None:
            return _create_category(session, body)
        return _update_category(session, body, category_id)
    except HTTPException:
        raise
    except IntegrityError:
        raise HTTPException(status_code=409, detail="Category mutation conflicts with an existing hierarchy row")
    except (DataError, UnicodeEncodeError):
        raise HTTPException(status_code=409, detail="Category payload violates database constraints")
    except Exception:
        raise HTTPException(status_code=409, detail="Category payload violates database constraints")


def _write_one(session, transaction_id: str, nys_snw_category_id: Optional[int]) -> ClassificationWriteResponse:
    posted_row = session.execute(
        text(
            """
        SELECT 1
          FROM teller.transaction
         WHERE transaction_id = :transaction_id
           AND status = 'posted'
         LIMIT 1
    """
        ),
        {"transaction_id": transaction_id},
    ).fetchone()
    if not posted_row:
        raise HTTPException(status_code=404, detail=f"Unknown transaction_id: {transaction_id}")
    if nys_snw_category_id is None:
        session.execute(
            text("DELETE FROM teller.transaction_nys_snw_category WHERE transaction_id = :transaction_id"),
            {"transaction_id": transaction_id},
        )
        session.commit()
        return ClassificationWriteResponse(
            transaction_id=transaction_id,
            nys_snw_category_id=None,
            updated_at=datetime.now(timezone.utc),
        )
    _ensure_exists(session, "nys_snw_category", "nys_snw_category_id", nys_snw_category_id, f"Unknown nys_snw_category_id: {nys_snw_category_id}")
    updated = session.execute(
        text(
            """
        UPDATE teller.transaction_nys_snw_category
           SET nys_snw_category_id = :nys_snw_category_id, type = 'user', updated_at = CURRENT_TIMESTAMP
         WHERE transaction_id = :transaction_id
     RETURNING updated_at
    """
        ),
        {"transaction_id": transaction_id, "nys_snw_category_id": nys_snw_category_id},
    ).fetchone()
    if not updated:
        updated = session.execute(
            text(
                """
            INSERT INTO teller.transaction_nys_snw_category (transaction_id, nys_snw_category_id, type)
            VALUES (:transaction_id, :nys_snw_category_id, 'user')
         RETURNING updated_at
        """
            ),
            {"transaction_id": transaction_id, "nys_snw_category_id": nys_snw_category_id},
        ).fetchone()
    updated_at = updated[0]
    if isinstance(updated_at, datetime) and updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)
    session.commit()
    return ClassificationWriteResponse(
        transaction_id=transaction_id,
        nys_snw_category_id=nys_snw_category_id,
        updated_at=updated_at,
    )


def _read_match_row(session, match_id: int) -> Dict[str, Any]:
    row = session.execute(
        text(
            """
        SELECT m.match_id,
               m.transaction_id,
               m.email_message_id,
               m.state AS state,
               m.selected_by AS selected_by
          FROM teller.transaction_email_match m
         WHERE m.match_id = :match_id
         LIMIT 1
    """
        ),
        {"match_id": match_id},
    ).mappings().fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"Unknown match_id: {match_id}")
    return dict(row)


def _read_active_match_row(session, match_id: int) -> Dict[str, Any]:
    row = session.execute(
        text(
            """
        SELECT m.match_id,
               m.transaction_id,
               m.email_message_id,
               m.state AS state,
               m.selected_by AS selected_by
          FROM teller.transaction_email_match m
         WHERE m.match_id = :match_id
           AND m.active = TRUE
         LIMIT 1
    """
        ),
        {"match_id": match_id},
    ).mappings().fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"Unknown match_id: {match_id}")
    return dict(row)


def _read_active_match_for_transaction(session, transaction_id: str) -> Dict[str, Any]:
    row = session.execute(
        text(
            """
        SELECT m.match_id,
               m.transaction_id,
               m.email_message_id,
               m.state AS state,
               m.selected_by AS selected_by
          FROM teller.transaction_email_match m
         WHERE m.transaction_id = :transaction_id
           AND m.active = TRUE
         ORDER BY m.selected_at DESC, m.match_id DESC
         LIMIT 1
    """
        ),
        {"transaction_id": transaction_id},
    ).mappings().fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"No active match for transaction_id: {transaction_id}")
    return dict(row)


def _active_match_candidate_row_payload(email_message_id: str) -> Dict[str, Any]:
    # Candidate-row shape for an active matched email that is not part of the latest match run
    # (e.g. a manual override against a searched email). It carries no candidate_id/score so the
    # Mailcart enrichment path treats it as a cold row and fills subject/sender/snippet, and the
    # cache-write step skips it (no candidate_id to update).
    return {
        "candidate_id": None,
        "email_message_id": email_message_id,
        "score": 0.0,
        "reason_json": {},
        "email_received_at": None,
        "is_selected_by_ai": False,
        "is_unmatched_email_priority": False,
        "cached_subject": None,
        "cached_sender": None,
        "cached_snippet": None,
        "cached_fetched_at": None,
    }


def _insert_match_audit(session, match_id: int, from_state: Optional[str], to_state: str, actor: str, note: Optional[str]) -> None:
    session.execute(
        _INSERT_MATCH_AUDIT_SQL,
        {
            "match_id": match_id,
            "from_state": from_state,
            "to_state": to_state,
            "actor": actor,
            "note": note,
        },
    )


def _transition_match_state(
    session,
    match_id: int,
    to_state: str,
    actor: str,
    note: Optional[str],
    email_message_id: Optional[str] = None,
    clear_email_message_id: bool = False,
    *,
    read_match_row_fn=_read_match_row,
    insert_match_audit_fn=_insert_match_audit,
) -> MatchReviewActionResponse:
    row = read_match_row_fn(session, match_id)
    values: Dict[str, object] = {
        "state": cast(bindparam("to_state"), _MATCH_STATE_ENUM),
        "selected_by": cast(bindparam("actor"), _MATCH_SELECTED_BY_ENUM),
        "selected_at": func.current_timestamp(),
        "updated_at": func.current_timestamp(),
    }
    if clear_email_message_id:
        values["email_message_id"] = None
    elif email_message_id is not None:
        values["email_message_id"] = bindparam("email_message_id")
    params = {
        "target_match_id": match_id,
        "to_state": to_state,
        "actor": actor,
    }
    if email_message_id is not None:
        params["email_message_id"] = email_message_id
    statement = (
        update(_MATCH_REVIEW_TABLE)
        .where(_MATCH_REVIEW_TABLE.c.match_id == bindparam("target_match_id"))
        .values(**values)
        .returning(
            _MATCH_REVIEW_TABLE.c.transaction_id,
            cast(_MATCH_REVIEW_TABLE.c.state, String).label("state"),
            cast(_MATCH_REVIEW_TABLE.c.selected_by, String).label("selected_by"),
            _MATCH_REVIEW_TABLE.c.updated_at,
        )
    )
    try:
        updated = session.execute(statement, params).mappings().fetchone()
        if not updated:
            raise HTTPException(status_code=404, detail=f"Unknown match_id: {match_id}")
        insert_match_audit_fn(session, match_id, row["state"], to_state, actor, note)
        session.commit()
    except HTTPException:
        raise
    except (IntegrityError, DataError):
        if hasattr(session, "rollback"):
            session.rollback()
        raise HTTPException(status_code=409, detail="Match state transition conflicts with current state")
    return MatchReviewActionResponse(
        match_id=match_id,
        transaction_id=updated["transaction_id"],
        state=updated["state"],
        selected_by=updated["selected_by"],
        updated_at=updated["updated_at"],
    )


def _deactivate_match(
    session,
    match_id: int,
    note: Optional[str],
    *,
    read_active_match_row_fn=_read_active_match_row,
    insert_match_audit_fn=_insert_match_audit,
) -> MatchReviewActionResponse:
    row = read_active_match_row_fn(session, match_id)
    from_state = row["state"]
    statement = (
        update(_MATCH_REVIEW_TABLE)
        .where(_MATCH_REVIEW_TABLE.c.match_id == bindparam("target_match_id"))
        .where(_MATCH_REVIEW_TABLE.c.active.is_(True))
        .values(
            active=False,
            updated_at=func.current_timestamp(),
        )
        .returning(
            _MATCH_REVIEW_TABLE.c.transaction_id,
            cast(_MATCH_REVIEW_TABLE.c.state, String).label("state"),
            cast(_MATCH_REVIEW_TABLE.c.selected_by, String).label("selected_by"),
            _MATCH_REVIEW_TABLE.c.updated_at,
        )
    )
    try:
        updated = session.execute(statement, {"target_match_id": match_id}).mappings().fetchone()
        if not updated:
            raise HTTPException(status_code=404, detail=f"Unknown match_id: {match_id}")
        insert_match_audit_fn(
            session,
            match_id,
            from_state,
            from_state,
            "human",
            note or "Cleared from Teller review UI",
        )
        session.commit()
    except HTTPException:
        raise
    except (IntegrityError, DataError):
        if hasattr(session, "rollback"):
            session.rollback()
        raise HTTPException(status_code=409, detail="Match deactivation conflicts with current state")
    updated_at = updated["updated_at"]
    if isinstance(updated_at, datetime) and updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)
    return MatchReviewActionResponse(
        match_id=match_id,
        transaction_id=updated["transaction_id"],
        state=updated["state"],
        selected_by=updated["selected_by"],
        updated_at=updated_at,
    )


def _ensure_posted_transaction(session, transaction_id: str) -> None:
    posted_row = session.execute(
        text(
            """
        SELECT 1
          FROM teller.transaction
         WHERE transaction_id = :transaction_id
           AND status = 'posted'
         LIMIT 1
    """
        ),
        {"transaction_id": transaction_id},
    ).fetchone()
    if not posted_row:
        raise HTTPException(status_code=404, detail=f"Unknown transaction_id: {transaction_id}")


def _ensure_no_active_match(session, transaction_id: str) -> None:
    existing = session.execute(
        text(
            """
        SELECT match_id
          FROM teller.transaction_email_match
         WHERE transaction_id = :transaction_id
           AND active = TRUE
         LIMIT 1
    """
        ),
        {"transaction_id": transaction_id},
    ).fetchone()
    if existing:
        raise HTTPException(
            status_code=409,
            detail="Transaction already has an active match; use /v1/matchy/matches/{match_id} mutation endpoints",
        )


def _ensure_candidate_for_transaction(session, transaction_id: str, email_message_id: str) -> None:
    latest = session.execute(_LATEST_MATCH_RUN_SQL, {"transaction_id": transaction_id}).fetchone()
    if not latest:
        raise HTTPException(status_code=404, detail=f"No match runs recorded for transaction_id: {transaction_id}")
    candidate = session.execute(
        text(
            """
        SELECT 1
          FROM teller.transaction_email_candidate
         WHERE match_run_id = :match_run_id
           AND email_message_id = :email_message_id
         LIMIT 1
    """
        ),
        {"match_run_id": latest[0], "email_message_id": email_message_id},
    ).fetchone()
    if not candidate:
        raise HTTPException(
            status_code=409,
            detail="email_message_id is not a candidate for the latest match run of this transaction",
        )


def _create_transaction_match(
    session,
    transaction_id: str,
    to_state: str,
    actor: str,
    note: Optional[str],
    email_message_id: Optional[str] = None,
    ai_confidence: Optional[float] = None,
    *,
    ensure_posted_transaction_fn=_ensure_posted_transaction,
    ensure_no_active_match_fn=_ensure_no_active_match,
    ensure_candidate_for_transaction_fn=_ensure_candidate_for_transaction,
    insert_match_audit_fn=_insert_match_audit,
    validate_email_message_id_fn=_validate_email_message_id,
    require_latest_candidate: bool = True,
) -> MatchReviewActionResponse:
    ensure_posted_transaction_fn(session, transaction_id)
    ensure_no_active_match_fn(session, transaction_id)
    if to_state == "ai_no_match_found":
        if email_message_id is not None:
            raise HTTPException(status_code=422, detail="email_message_id must be omitted for no-email matches")
    else:
        if not email_message_id:
            raise HTTPException(status_code=422, detail="email_message_id is required")
        validate_email_message_id_fn(email_message_id)
        if require_latest_candidate:
            ensure_candidate_for_transaction_fn(session, transaction_id, email_message_id)
    try:
        inserted = session.execute(
            _CREATE_MATCH_SQL,
            {
                "transaction_id": transaction_id,
                "email_message_id": email_message_id,
                "state": to_state,
                "ai_confidence": ai_confidence,
                "selected_by": actor,
            },
        ).mappings().fetchone()
        if not inserted:
            raise HTTPException(status_code=500, detail="Failed to create match row")
        match_id = int(inserted["match_id"])
        updated_at = inserted["updated_at"]
        if isinstance(updated_at, datetime) and updated_at.tzinfo is None:
            updated_at = updated_at.replace(tzinfo=timezone.utc)
        insert_match_audit_fn(session, match_id, None, to_state, actor, note)
        session.commit()
    except HTTPException:
        raise
    except (IntegrityError, DataError):
        if hasattr(session, "rollback"):
            session.rollback()
        raise HTTPException(status_code=409, detail="Match creation conflicts with existing active email link")
    return MatchReviewActionResponse(
        match_id=match_id,
        transaction_id=transaction_id,
        state=to_state,
        selected_by=actor,
        updated_at=updated_at,
    )


def _create_transaction_match_allowing_non_candidate_email(
    session,
    transaction_id: str,
    to_state: str,
    actor: str,
    note: Optional[str],
    email_message_id: str,
    ai_confidence: Optional[float] = None,
    *,
    ensure_posted_transaction_fn=_ensure_posted_transaction,
    ensure_no_active_match_fn=_ensure_no_active_match,
    insert_match_audit_fn=_insert_match_audit,
    validate_email_message_id_fn=_validate_email_message_id,
) -> MatchReviewActionResponse:
    return _create_transaction_match(
        session=session,
        transaction_id=transaction_id,
        to_state=to_state,
        actor=actor,
        note=note,
        email_message_id=email_message_id,
        ai_confidence=ai_confidence,
        ensure_posted_transaction_fn=ensure_posted_transaction_fn,
        ensure_no_active_match_fn=ensure_no_active_match_fn,
        insert_match_audit_fn=insert_match_audit_fn,
        validate_email_message_id_fn=validate_email_message_id_fn,
        require_latest_candidate=False,
    )
