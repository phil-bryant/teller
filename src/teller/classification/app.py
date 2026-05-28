from __future__ import annotations

from datetime import date
from decimal import Decimal, InvalidOperation
from types import SimpleNamespace
from typing import Dict, List, Literal

from fastapi import FastAPI, HTTPException, Path, Query, Request, Response
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import String, bindparam, cast, func, select, text
from sqlalchemy.exc import DataError

from teller.classification import auth, mailcart, services
from teller.classification.constants import (
    _EMAIL_MESSAGE_ID_PATTERN,
    _EMAIL_SEARCH_QUERY_PATTERN,
    _LATEST_MATCH_RUN_SQL,
    _LATEST_RUN_CANDIDATES_SQL,
    _MATCH_REVIEW_TABLE,
    _TRANSACTION_COUNT_SQL,
    _TRANSACTION_LIST_SQL,
    _TRANSACTION_TABLE,
)
from teller.classification.schemas import (
    ApiError,
    CategoryCountsRow,
    CategoryCreateMutation,
    CategoryDeleteResponse,
    CategoryOption,
    CategoryUpdateMutation,
    ClassificationBatchRequest,
    ClassificationWriteResponse,
    EmailMessage,
    EmailSearchResponse,
    MatchCandidateRow,
    MatchOverrideMutation,
    MatchReviewActionResponse,
    MatchReviewListResponse,
    MatchReviewRow,
    SingleClassificationMutation,
    TransactionCategory,
    TransactionListResponse,
    TransactionMatchInfo,
    TransactionRow,
)
from teller.classification.text import _display_label
from teller.teller_db import get_session
from teller.teller_mailcart_client import MailcartError, get_mailcart_client

_EXPECTED_DATE_FORMAT = "YYYY-MM-DD"


def _date_format_error_detail(field_name: str) -> str:
    return f"Expected date format: {_EXPECTED_DATE_FORMAT} for {field_name}"


def _friendly_date_validation_detail(errors: list[dict]) -> str | None:
    for err in errors:
        if not isinstance(err, dict):
            continue
        loc = err.get("loc")
        if not isinstance(loc, (list, tuple)) or len(loc) < 2:
            continue
        if loc[0] != "query":
            continue
        field_name = loc[1]
        if field_name in {"start_date", "end_date"}:
            return _date_format_error_detail(str(field_name))
    return None


def _resolve_bindings(bindings=None):
    if bindings is not None:
        return bindings
    return SimpleNamespace(
        get_session=get_session,
        get_mailcart_client=get_mailcart_client,
        _require_authenticated_access=auth._require_authenticated_access,
        _require_write_access=auth._require_write_access,
        _estimate_transaction_total=services._estimate_transaction_total,
        _write_category=services._write_category,
        _write_one=services._write_one,
        _ensure_exists=services._ensure_exists,
        _fetch_category=services._fetch_category,
        _match_review_filters=services._match_review_filters,
        _transition_match_state=services._transition_match_state,
        _deactivate_match=services._deactivate_match,
        _create_transaction_match=services._create_transaction_match,
        _ensure_posted_transaction=services._ensure_posted_transaction,
        _read_active_match_for_transaction=services._read_active_match_for_transaction,
        _enrich_candidates_with_mailcart=mailcart._enrich_candidates_with_mailcart,
        _email_search_hit_from_payload=mailcart._email_search_hit_from_payload,
        _email_message_from_payload=mailcart._email_message_from_payload,
        _validate_email_message_id=services._validate_email_message_id,
    )


def _register_health_routes(app: FastAPI) -> None:
    @app.get("/health")
    def health():
        return {"ok": True}


def _register_category_routes(app: FastAPI, bindings) -> None:
    @app.get("/v1/categories", response_model=List[CategoryOption])
    def list_categories(request: Request):
        bindings._require_authenticated_access(request)
        with bindings.get_session() as session:
            rows = session.execute(
                text(
                    """
                SELECT nys_snw_category_id, level_1, level_1_name, level_2, level_2_name, level_3, level_4,
                       categorization, applicability
                  FROM teller.nys_snw_category
                 ORDER BY level_1, level_2, level_3, level_4, categorization, nys_snw_category_id
            """
                )
            ).mappings().all()
        return [CategoryOption(**row, display_label=_display_label(row)) for row in rows]

    @app.post(
        "/v1/categories",
        response_model=CategoryOption,
        responses={
            400: {"model": ApiError, "description": "Invalid category payload"},
            422: {"model": ApiError, "description": "Malformed category payload"},
            409: {"model": ApiError, "description": "Category hierarchy conflicts with existing row"},
        },
    )
    def create_category(request: Request, body: CategoryCreateMutation):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            return bindings._write_category(session, body)

    @app.put(
        "/v1/categories/{nys_snw_category_id:int}",
        response_model=CategoryOption,
        responses={
            400: {"model": ApiError, "description": "Invalid category payload"},
            422: {"model": ApiError, "description": "Malformed category payload"},
            409: {"model": ApiError, "description": "Category hierarchy conflicts with existing row"},
            404: {"model": ApiError, "description": "Unknown category id"},
        },
    )
    def update_category(request: Request, nys_snw_category_id: int, body: CategoryUpdateMutation):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            return bindings._write_category(session, body, category_id=nys_snw_category_id)

    @app.delete(
        "/v1/categories/{nys_snw_category_id:int}",
        response_model=CategoryDeleteResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown category id"},
            409: {"model": ApiError, "description": "Category still referenced by transactions"},
        },
    )
    def delete_category(request: Request, nys_snw_category_id: int):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            bindings._ensure_exists(session, "nys_snw_category", "nys_snw_category_id", nys_snw_category_id, f"Unknown nys_snw_category_id: {nys_snw_category_id}")
            category_row = bindings._fetch_category(session, nys_snw_category_id)
            if category_row.get("is_seed"):
                raise HTTPException(
                    status_code=409,
                    detail=f"Category {nys_snw_category_id} is seed-protected and cannot be deleted.",
                )
            assignment_count = session.execute(
                text(
                    """
                SELECT COUNT(*)::INT
                  FROM teller.transaction_nys_snw_category
                 WHERE nys_snw_category_id = :nys_snw_category_id
            """
                ),
                {"nys_snw_category_id": nys_snw_category_id},
            ).scalar_one()
            if assignment_count > 0:
                raise HTTPException(
                    status_code=409,
                    detail=f"Cannot delete category {nys_snw_category_id}; {assignment_count} transaction(s) still reference it.",
                )
            session.execute(
                text(
                    """
                DELETE FROM teller.nys_snw_category
                 WHERE nys_snw_category_id = :nys_snw_category_id
            """
                ),
                {"nys_snw_category_id": nys_snw_category_id},
            )
            session.commit()
        return CategoryDeleteResponse(nys_snw_category_id=nys_snw_category_id)

    @app.get("/v1/categories/counts", response_model=List[CategoryCountsRow])
    def category_counts(request: Request):
        bindings._require_authenticated_access(request)
        with bindings.get_session() as session:
            rows = session.execute(
                text(
                    """
                SELECT c.nys_snw_category_id, c.level_1, c.level_1_name, c.level_2, c.level_2_name, c.level_3, c.level_4,
                       c.categorization, COUNT(tc.transaction_id)::INT AS assigned_transactions
                  FROM teller.nys_snw_category c
             LEFT JOIN teller.transaction_nys_snw_category tc USING (nys_snw_category_id)
              GROUP BY c.nys_snw_category_id, c.level_1, c.level_1_name, c.level_2, c.level_2_name, c.level_3, c.level_4,
                       c.categorization
              ORDER BY assigned_transactions DESC, c.level_1, c.level_2, c.level_3
            """
                )
            ).mappings().all()
        return [
            CategoryCountsRow(
                nys_snw_category_id=row["nys_snw_category_id"],
                display_label=_display_label(row),
                assigned_transactions=row["assigned_transactions"],
            )
            for row in rows
        ]

    @app.api_route("/v1/categories/counts", methods=["POST", "PUT", "PATCH", "DELETE"], include_in_schema=False)
    def category_counts_method_not_allowed():
        return Response(status_code=405, headers={"Allow": "GET"})


def _register_transaction_routes(app: FastAPI, bindings) -> None:
    def _parse_optional_date(value: str | None, field_name: str) -> date | None:
        if value is None:
            return None
        if isinstance(value, date):
            return value
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"", "null"}:
                return None
            try:
                return date.fromisoformat(normalized)
            except ValueError:
                raise HTTPException(status_code=400, detail=_date_format_error_detail(field_name))
        # Direct endpoint invocations in unit tests may pass FastAPI Query marker objects.
        return None

    def _parse_optional_amount(value: str | None, field_name: str) -> Decimal | None:
        if value is None:
            return None
        parsed: Decimal | None = None
        if isinstance(value, Decimal):
            parsed = value
        elif isinstance(value, (int, float)):
            parsed = Decimal(str(value))
        elif isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"", "null"}:
                return None
            try:
                parsed = Decimal(normalized)
            except (InvalidOperation, ValueError):
                raise HTTPException(
                    status_code=422,
                    detail=[{"loc": ["query", field_name], "msg": "Input should be a valid decimal", "type": "decimal_parsing"}],
                )
        else:
            # Direct endpoint invocations in unit tests may pass FastAPI Query marker objects.
            return None
        if parsed is None:
            return None
        if parsed < 0:
            raise HTTPException(
                status_code=422,
                detail=[{"loc": ["query", field_name], "msg": "Input should be greater than or equal to 0", "type": "greater_than_equal"}],
            )
        return parsed

    @app.get(
        "/v1/transactions",
        response_model=TransactionListResponse,
        responses={
            400: {"model": ApiError, "description": "Invalid query parameter value"},
            422: {"model": ApiError, "description": "Malformed query parameter value"},
            500: {"model": ApiError, "description": "Unexpected server error"},
        },
    )
    def list_transactions(
        request: Request,
        search: str = Query(default="", min_length=0, max_length=120, pattern=r"^[\x20-\x7E]*$"),
        status: Literal["", "posted", "pending"] = Query(default=""),
        only_unclassified: bool = Query(default=False),
        match_state: Literal["", "unmatched", "no_email", "ai_no_match_found", "ai_candidate_uncertain", "ai_match_confident", "human_confirmed_ai_match", "human_overrode_ai_match"] = Query(default=""),
        only_unmoved_match: bool = Query(default=False),
        #R075: Support advanced scalar filters used by the macOS Match & Classify transaction pane.
        start_date: str | None = Query(default=None, max_length=20, pattern=r"^(null|[0-9]{4}-[0-9]{2}-[0-9]{2})?$"),
        end_date: str | None = Query(default=None, max_length=20, pattern=r"^(null|[0-9]{4}-[0-9]{2}-[0-9]{2})?$"),
        institution_id: str = Query(default="", min_length=0, max_length=120, pattern=r"^[\x20-\x7E]*$"),
        min_amount: str | None = Query(default=None, max_length=40, pattern=r"^(null|[0-9]+(?:\.[0-9]+)?)?$"),
        max_amount: str | None = Query(default=None, max_length=40, pattern=r"^(null|[0-9]+(?:\.[0-9]+)?)?$"),
        include_total: bool = Query(default=True),
        count_only: bool = Query(default=False),
        limit: int = Query(default=150, ge=1, le=500),
        offset: int = Query(default=0, ge=0, le=1_000_000),
    ):
        bindings._require_authenticated_access(request)
        allowed_query_params = {
            "search",
            "status",
            "only_unclassified",
            "match_state",
            "only_unmoved_match",
            "start_date",
            "end_date",
            "institution_id",
            "min_amount",
            "max_amount",
            "include_total",
            "count_only",
            "limit",
            "offset",
        }
        unknown_params = sorted(set(request.query_params.keys()) - allowed_query_params)
        if unknown_params:
            raise HTTPException(status_code=400, detail=f"Unknown query parameters: {', '.join(unknown_params)}")
        only_unclassified_raw = request.query_params.get("only_unclassified")
        if only_unclassified_raw is not None and only_unclassified_raw.lower() not in {"true", "false"}:
            raise HTTPException(
                status_code=422,
                detail=[
                    {
                        "loc": ["query", "only_unclassified"],
                        "msg": "Input should be a valid boolean, unable to interpret input",
                        "type": "bool_parsing",
                    }
                ],
            )
        normalized_institution_id = institution_id.strip() if isinstance(institution_id, str) else ""
        params = {
            "search": search,
            "search_pattern": f"%{search}%" if search else "",
            "status": status,
            "only_unclassified": only_unclassified,
            "match_state": match_state,
            "only_unmoved_match": only_unmoved_match,
            "start_date": _parse_optional_date(start_date, "start_date"),
            "end_date": _parse_optional_date(end_date, "end_date"),
            "institution_id": normalized_institution_id,
            "min_amount": _parse_optional_amount(min_amount, "min_amount"),
            "max_amount": _parse_optional_amount(max_amount, "max_amount"),
            "limit": limit,
            "offset": offset,
        }
        try:
            with bindings.get_session() as session:
                if count_only:
                    total = session.execute(_TRANSACTION_COUNT_SQL, params).scalar_one()
                    return TransactionListResponse(total=total, items=[])
                rows = session.execute(_TRANSACTION_LIST_SQL, params).mappings().all()
                if include_total:
                    total = session.execute(_TRANSACTION_COUNT_SQL, params).scalar_one()
                else:
                    total = bindings._estimate_transaction_total(offset=offset, limit=limit, row_count=len(rows))
        except HTTPException:
            raise
        except (DataError, UnicodeEncodeError):
            raise HTTPException(status_code=400, detail="Invalid query parameter value")
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid query parameter value")

        items = []
        for row in rows:
            classification = None
            if row["nys_snw_category_id"]:
                classification = TransactionCategory(
                    nys_snw_category_id=row["nys_snw_category_id"],
                    display_label=_display_label(row),
                )
            match_info = None
            if row.get("match_id") is not None:
                match_info = TransactionMatchInfo(
                    match_id=int(row["match_id"]),
                    email_message_id=row.get("match_email_message_id"),
                    state=str(row["match_state"]),
                    ai_confidence=float(row["match_ai_confidence"]) if row.get("match_ai_confidence") is not None else None,
                    selected_by=str(row["match_selected_by"]),
                    moved_to_matchy_at=row.get("moved_to_matchy_at"),
                    match_count=int(row.get("match_count") or 1),
                )
            items.append(
                TransactionRow(
                    transaction_id=row["transaction_id"],
                    account_id=row["account_id"],
                    institution_id=row["institution_id"],
                    account_last_four=row["account_last_four"],
                    date=row["date"],
                    amount=row["amount"],
                    description=row["description"],
                    status=row["status"],
                    transaction_type_code=row["transaction_type_code"],
                    teller_category=row["teller_category"],
                    classification=classification,
                    match=match_info,
                )
            )
        return TransactionListResponse(total=total, items=items)

    @app.put(
        "/v1/transactions/{transaction_id}/classification",
        response_model=ClassificationWriteResponse,
        responses={
            400: {"model": ApiError, "description": "Malformed request body"},
            404: {"model": ApiError, "description": "Unknown transaction or category id"},
        },
    )
    def set_classification(request: Request, transaction_id: str, body: SingleClassificationMutation):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            return bindings._write_one(session, transaction_id, body.nys_snw_category_id)

    @app.post(
        "/v1/transactions/classifications",
        response_model=List[ClassificationWriteResponse],
        responses={
            404: {"model": ApiError, "description": "Unknown transaction or category id"},
        },
    )
    def set_classifications(request: Request, body: ClassificationBatchRequest):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            responses = [bindings._write_one(session, item.transaction_id, item.nys_snw_category_id) for item in body.updates]
        return responses


def _register_matchy_routes(app: FastAPI, bindings) -> None:
    def _search_text(value: object) -> str:
        if not isinstance(value, str):
            return ""
        return value.strip()

    def _search_date(value: object) -> str | None:
        if isinstance(value, date):
            return value.isoformat()
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"", "null"}:
                return None
            return normalized
        return None

    def _effective_email_search_query(
        *,
        subject: str,
        sender: str,
        body: str,
        start_date: str | None,
        end_date: str | None,
    ) -> str:
        parts = []
        if subject:
            parts.append(f"subject:{subject}")
        if sender:
            parts.append(f"sender:{sender}")
        if body:
            parts.append(f"body:{body}")
        if start_date is not None:
            parts.append(f"from:{start_date}")
        if end_date is not None:
            parts.append(f"to:{end_date}")
        if parts:
            return " ".join(parts)
        return ""

    @app.get(
        "/v1/matchy/review",
        response_model=MatchReviewListResponse,
        responses={
            400: {"model": ApiError, "description": "Invalid query parameter"},
        },
    )
    def list_matchy_review(
        request: Request,
        state: Literal["", "ai_no_match_found", "ai_candidate_uncertain", "ai_match_confident", "human_confirmed_ai_match", "human_overrode_ai_match"] = Query(default=""),
        only_unmoved: bool = Query(default=False),
        limit: int = Query(default=100, ge=1, le=500),
        offset: int = Query(default=0, ge=0, le=1_000_000),
    ):
        bindings._require_authenticated_access(request)
        allowed_query_params = {"state", "only_unmoved", "limit", "offset"}
        request_query_params = getattr(request, "query_params", {})
        query_param_keys = request_query_params.keys() if hasattr(request_query_params, "keys") else []
        unknown_params = sorted(set(query_param_keys) - allowed_query_params)
        if unknown_params:
            raise HTTPException(status_code=400, detail=f"Unknown query parameters: {', '.join(unknown_params)}")
        filters = bindings._match_review_filters(state=state, only_unmoved=only_unmoved)
        params: Dict[str, object] = {"limit": limit, "offset": offset}
        if state:
            params["state"] = state
        total_stmt = select(func.count()).select_from(_MATCH_REVIEW_TABLE).where(*filters)
        rows_stmt = (
            select(
                _MATCH_REVIEW_TABLE.c.match_id,
                _MATCH_REVIEW_TABLE.c.transaction_id,
                _MATCH_REVIEW_TABLE.c.email_message_id,
                cast(_MATCH_REVIEW_TABLE.c.state, String).label("state"),
                _MATCH_REVIEW_TABLE.c.ai_confidence,
                cast(_MATCH_REVIEW_TABLE.c.selected_by, String).label("selected_by"),
                _MATCH_REVIEW_TABLE.c.selected_at,
                _MATCH_REVIEW_TABLE.c.moved_to_matchy_at,
                _TRANSACTION_TABLE.c.description,
                _TRANSACTION_TABLE.c.amount,
                _TRANSACTION_TABLE.c.date,
            )
            .select_from(
                _MATCH_REVIEW_TABLE.join(
                    _TRANSACTION_TABLE,
                    _TRANSACTION_TABLE.c.transaction_id == _MATCH_REVIEW_TABLE.c.transaction_id,
                )
            )
            .where(*filters)
            .order_by(_MATCH_REVIEW_TABLE.c.selected_at.desc(), _MATCH_REVIEW_TABLE.c.match_id.desc())
            .limit(bindparam("limit"))
            .offset(bindparam("offset"))
        )
        with bindings.get_session() as session:
            total = session.execute(total_stmt, params).scalar_one()
            rows = session.execute(rows_stmt, params).mappings().all()
        items = [MatchReviewRow(**row) for row in rows]
        return MatchReviewListResponse(total=total, items=items)

    @app.put(
        "/v1/matchy/matches/{match_id:int}/confirm",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown match id"},
            409: {"model": ApiError, "description": "Match state transition conflicts with current state"},
        },
    )
    def confirm_match(request: Request, match_id: int):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            return bindings._transition_match_state(
                session=session,
                match_id=match_id,
                to_state="human_confirmed_ai_match",
                actor="human",
                note="Confirmed from Teller review UI",
            )

    @app.put(
        "/v1/matchy/matches/{match_id:int}/override",
        response_model=MatchReviewActionResponse,
        responses={
            400: {"model": ApiError, "description": "Malformed request body"},
            404: {"model": ApiError, "description": "Unknown match id"},
            409: {"model": ApiError, "description": "Match state transition conflicts with current state"},
        },
    )
    def override_match(request: Request, match_id: int, body: MatchOverrideMutation):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            return bindings._transition_match_state(
                session=session,
                match_id=match_id,
                to_state="human_overrode_ai_match",
                actor="human",
                note=body.note or "Overridden from Teller review UI",
                email_message_id=body.email_message_id,
            )

    @app.put(
        "/v1/matchy/matches/{match_id:int}/no-email",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown match id"},
            409: {"model": ApiError, "description": "Match state transition conflicts with current state"},
        },
    )
    def mark_match_as_no_email(request: Request, match_id: int):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            return bindings._transition_match_state(
                session=session,
                match_id=match_id,
                to_state="ai_no_match_found",
                actor="human",
                note="Marked no-email from Teller review UI",
                clear_email_message_id=True,
            )

    @app.put(
        "/v1/matchy/matches/{match_id:int}/clear",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown match id or no active match"},
            409: {"model": ApiError, "description": "Match deactivation conflicts with current state"},
        },
    )
    def clear_match(request: Request, match_id: int):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            return bindings._deactivate_match(session=session, match_id=match_id, note="Cleared from Teller review UI")

    @app.put(
        "/v1/matchy/transactions/{transaction_id}/confirm-candidate",
        response_model=MatchReviewActionResponse,
        responses={
            400: {"model": ApiError, "description": "Malformed request body or invalid email message identifier"},
            404: {"model": ApiError, "description": "Unknown transaction or no match runs recorded"},
            409: {"model": ApiError, "description": "Transaction already has an active match or email link conflict"},
        },
    )
    def confirm_transaction_candidate(request: Request, transaction_id: str, body: MatchOverrideMutation):
        bindings._require_write_access(request)
        try:
            with bindings.get_session() as session:
                return bindings._create_transaction_match(
                    session=session,
                    transaction_id=transaction_id,
                    email_message_id=body.email_message_id,
                    to_state="human_confirmed_ai_match",
                    actor="human",
                    note=body.note or "Confirmed candidate from Teller review UI",
                )
        except HTTPException as exc:
            if exc.status_code == 422:
                raise HTTPException(status_code=409, detail=exc.detail)
            raise

    @app.put(
        "/v1/matchy/transactions/{transaction_id}/override-candidate",
        response_model=MatchReviewActionResponse,
        responses={
            400: {"model": ApiError, "description": "Malformed request body or invalid email message identifier"},
            404: {"model": ApiError, "description": "Unknown transaction or no match runs recorded"},
            409: {"model": ApiError, "description": "Transaction already has an active match or email link conflict"},
        },
    )
    def override_transaction_candidate(request: Request, transaction_id: str, body: MatchOverrideMutation):
        bindings._require_write_access(request)
        try:
            with bindings.get_session() as session:
                return bindings._create_transaction_match(
                    session=session,
                    transaction_id=transaction_id,
                    email_message_id=body.email_message_id,
                    to_state="human_overrode_ai_match",
                    actor="human",
                    note=body.note or "Overridden from Teller review UI",
                )
        except HTTPException as exc:
            if exc.status_code == 422:
                raise HTTPException(status_code=409, detail=exc.detail)
            raise

    @app.put(
        "/v1/matchy/transactions/{transaction_id}/no-email",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown transaction"},
            409: {"model": ApiError, "description": "Transaction already has an active match"},
        },
    )
    def mark_transaction_no_email(request: Request, transaction_id: str):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            return bindings._create_transaction_match(
                session=session,
                transaction_id=transaction_id,
                to_state="ai_no_match_found",
                actor="human",
                note="Marked no-email from Teller review UI",
            )

    @app.put(
        "/v1/matchy/transactions/{transaction_id}/clear",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown transaction or no active match"},
            409: {"model": ApiError, "description": "Match deactivation conflicts with current state"},
        },
    )
    def clear_transaction_match(request: Request, transaction_id: str):
        bindings._require_write_access(request)
        with bindings.get_session() as session:
            bindings._ensure_posted_transaction(session, transaction_id)
            row = bindings._read_active_match_for_transaction(session, transaction_id)
            return bindings._deactivate_match(
                session=session,
                match_id=int(row["match_id"]),
                note="Cleared from Teller review UI",
            )

    @app.get(
        "/v1/matchy/transactions/{transaction_id}/candidates",
        response_model=List[MatchCandidateRow],
        response_model_by_alias=True,
        responses={
            503: {"model": ApiError, "description": "Mailcart is not configured"},
        },
    )
    def list_match_candidates(request: Request, transaction_id: str):
        bindings._require_authenticated_access(request)
        with bindings.get_session() as session:
            latest = session.execute(_LATEST_MATCH_RUN_SQL, {"transaction_id": transaction_id}).fetchone()
            if not latest:
                # A missing run is a common pre-match state for newly loaded transactions.
                # Return an empty candidate set so the UI can render this as "no candidates yet"
                # instead of surfacing a transport-level error.
                return []
            candidate_rows = session.execute(_LATEST_RUN_CANDIDATES_SQL, {"match_run_id": latest[0]}).mappings().all()
            if not candidate_rows:
                return []
            return bindings._enrich_candidates_with_mailcart(session, candidate_rows)

    @app.get(
        "/v1/matchy/messages/search",
        response_model=EmailSearchResponse,
        response_model_by_alias=True,
        responses={
            400: {"model": ApiError, "description": "Invalid query parameter"},
            422: {"model": ApiError, "description": "Missing or malformed structured search criteria"},
            502: {"model": ApiError, "description": "Mailcart upstream returned an unexpected response"},
            503: {"model": ApiError, "description": "Mailcart is not configured"},
        },
    )
    def search_match_messages(
        request: Request,
        subject: str | None = Query(default=None, min_length=1, max_length=200, pattern=_EMAIL_SEARCH_QUERY_PATTERN),
        sender: str | None = Query(default=None, min_length=1, max_length=200, pattern=_EMAIL_SEARCH_QUERY_PATTERN),
        body: str | None = Query(default=None, min_length=1, max_length=200, pattern=_EMAIL_SEARCH_QUERY_PATTERN),
        start_date: str | None = Query(default=None, max_length=20, pattern=r"^(null|[0-9]{4}-[0-9]{2}-[0-9]{2})?$"),
        end_date: str | None = Query(default=None, max_length=20, pattern=r"^(null|[0-9]{4}-[0-9]{2}-[0-9]{2})?$"),
        limit: int = Query(default=25, ge=1, le=100),
    ):
        bindings._require_authenticated_access(request)
        allowed_query_params = {"subject", "sender", "body", "start_date", "end_date", "limit"}
        unknown_params = sorted(set(request.query_params.keys()) - allowed_query_params)
        if unknown_params:
            raise HTTPException(status_code=400, detail=f"Unknown query parameters: {', '.join(unknown_params)}")
        effective_query = _effective_email_search_query(
            subject=_search_text(subject),
            sender=_search_text(sender),
            body=_search_text(body),
            start_date=_search_date(start_date),
            end_date=_search_date(end_date),
        )
        client = bindings.get_mailcart_client()
        try:
            payload = client.search(query=effective_query, limit=limit)
        except MailcartError as exc:
            raise HTTPException(status_code=exc.status_code, detail=exc.message)
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"mailcart: request failed: {exc}") from exc
        hits_raw = None
        if isinstance(payload, dict):
            hits_raw = payload.get("messages")
            if not isinstance(hits_raw, list):
                hits_raw = payload.get("items")
        if not isinstance(hits_raw, list):
            raise HTTPException(status_code=502, detail="mailcart: search response missing 'messages' array")
        hits = [bindings._email_search_hit_from_payload(item) for item in hits_raw if isinstance(item, dict)]
        return EmailSearchResponse(query=effective_query, items=hits)

    @app.get(
        "/v1/matchy/messages/{email_message_id}",
        response_model=EmailMessage,
        response_model_by_alias=True,
        responses={
            400: {"model": ApiError, "description": "Invalid email message identifier"},
            404: {"model": ApiError, "description": "Unknown email message identifier"},
            502: {"model": ApiError, "description": "Mailcart upstream returned an unexpected response"},
            503: {"model": ApiError, "description": "Mailcart is not configured"},
        },
    )
    def get_match_message(
        request: Request,
        email_message_id: str = Path(
            ...,
            min_length=1,
            max_length=4096,
            pattern=_EMAIL_MESSAGE_ID_PATTERN,
        ),
    ):
        bindings._require_authenticated_access(request)
        bindings._validate_email_message_id(email_message_id)
        client = bindings.get_mailcart_client()
        try:
            payload = client.get_message(email_message_id)
        except MailcartError as exc:
            raise HTTPException(status_code=exc.status_code, detail=exc.message)
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"mailcart: request failed: {exc}") from exc
        return bindings._email_message_from_payload(email_message_id, payload)


def create_app(bindings=None) -> FastAPI:
    resolved_bindings = _resolve_bindings(bindings)
    app = FastAPI(title="Teller Classification API", version="0.1.0")

    @app.exception_handler(RequestValidationError)
    async def _request_validation_error_handler(request: Request, exc: RequestValidationError):
        if request.url.path == "/v1/transactions":
            friendly_detail = _friendly_date_validation_detail(exc.errors())
            if friendly_detail is not None:
                return JSONResponse(status_code=422, content={"detail": friendly_detail})
        return await request_validation_exception_handler(request, exc)

    _register_health_routes(app)
    _register_category_routes(app, resolved_bindings)
    _register_transaction_routes(app, resolved_bindings)
    _register_matchy_routes(app, resolved_bindings)
    return app
