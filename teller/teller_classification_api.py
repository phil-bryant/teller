from __future__ import annotations
import os
import re
import shutil
import unicodedata
from functools import lru_cache
from datetime import date, datetime, timezone
from decimal import Decimal
from subprocess import CalledProcessError, run as run_process  # nosec B404
from typing import Annotated, Any, Dict, List, Literal, Optional
from fastapi import FastAPI, HTTPException, Query, Request, Response
from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator
from sqlalchemy.exc import DataError, IntegrityError
from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Float,
    Integer,
    MetaData,
    Numeric,
    String,
    Table,
    bindparam,
    cast,
    func,
    select,
    text,
    update,
)
from sqlalchemy.dialects.postgresql import ENUM as PgEnum
from teller.teller_db import get_session
from teller.teller_mailcart_client import MailcartError, get_mailcart_client

_EXISTENCE_QUERIES = {
    ("nys_snw_category", "nys_snw_category_id"): text("""
        SELECT 1
          FROM teller.nys_snw_category
         WHERE nys_snw_category_id = :value
         LIMIT 1
    """),
}

#R070: `/v1/transactions` joins the latest active email-match row (one representative per transaction)
#R070: + a count of total active match rows so the unified Match & Classify UI can show classification
#R070: AND match status on each row in a single round-trip.
_TRANSACTION_COUNT_SQL = text("""
    SELECT COUNT(*)
      FROM teller.transaction tt
      LEFT JOIN teller.account ta USING (account_id)
      LEFT JOIN teller.transaction_type ttt USING (transaction_type_id)
      LEFT JOIN teller.transaction_details ttd USING (transaction_details_id)
      LEFT JOIN LATERAL (
          SELECT tnsc.nys_snw_category_id
            FROM teller.transaction_nys_snw_category tnsc
           WHERE tnsc.transaction_id = tt.transaction_id
           ORDER BY tnsc.updated_at DESC
           LIMIT 1
      ) m ON TRUE
      LEFT JOIN teller.nys_snw_category nsc ON nsc.nys_snw_category_id = m.nys_snw_category_id
      LEFT JOIN LATERAL (
          SELECT tem.match_id, tem.state::text AS state, tem.selected_by::text AS selected_by,
                 tem.email_message_id, tem.moved_to_matchy_at, tem.ai_confidence
            FROM teller.transaction_email_match tem
           WHERE tem.transaction_id = tt.transaction_id
             AND tem.active = TRUE
           ORDER BY tem.ai_confidence DESC NULLS LAST, tem.selected_at DESC, tem.match_id DESC
           LIMIT 1
      ) tem ON TRUE
     WHERE tt.status = 'posted'
       AND (:search = '' OR tt.description ILIKE :search_pattern OR tt.transaction_id ILIKE :search_pattern)
       AND (:status = '' OR tt.status::text = :status)
       AND (:only_unclassified = FALSE OR m.nys_snw_category_id IS NULL)
       AND (:match_state = '' OR tem.state = :match_state)
       AND (:only_unmoved_match = FALSE OR tem.match_id IS NULL OR tem.moved_to_matchy_at IS NULL)
""")

_TRANSACTION_LIST_SQL = text("""
    SELECT tt.transaction_id, tt.account_id, ta.institution_id, ta.last_four AS account_last_four,
           tt.date, tt.amount, tt.description, tt.status,
           ttt.code AS transaction_type_code, ttd.category AS teller_category,
           m.nys_snw_category_id, nsc.level_1, nsc.level_1_name, nsc.level_2, nsc.level_2_name,
           nsc.level_3, nsc.level_4, nsc.categorization,
           tem.match_id, tem.state AS match_state, tem.selected_by AS match_selected_by,
           tem.email_message_id AS match_email_message_id, tem.moved_to_matchy_at,
           tem.ai_confidence AS match_ai_confidence,
           (SELECT COUNT(*) FROM teller.transaction_email_match
             WHERE transaction_id = tt.transaction_id AND active = TRUE)::INT AS match_count
      FROM teller.transaction tt
      LEFT JOIN teller.account ta USING (account_id)
      LEFT JOIN teller.transaction_type ttt USING (transaction_type_id)
      LEFT JOIN teller.transaction_details ttd USING (transaction_details_id)
      LEFT JOIN LATERAL (
          SELECT tnsc.nys_snw_category_id
            FROM teller.transaction_nys_snw_category tnsc
           WHERE tnsc.transaction_id = tt.transaction_id
           ORDER BY tnsc.updated_at DESC
           LIMIT 1
      ) m ON TRUE
      LEFT JOIN teller.nys_snw_category nsc ON nsc.nys_snw_category_id = m.nys_snw_category_id
      LEFT JOIN LATERAL (
          SELECT tem.match_id, tem.state::text AS state, tem.selected_by::text AS selected_by,
                 tem.email_message_id, tem.moved_to_matchy_at, tem.ai_confidence
            FROM teller.transaction_email_match tem
           WHERE tem.transaction_id = tt.transaction_id
             AND tem.active = TRUE
           ORDER BY tem.ai_confidence DESC NULLS LAST, tem.selected_at DESC, tem.match_id DESC
           LIMIT 1
      ) tem ON TRUE
     WHERE tt.status = 'posted'
       AND (:search = '' OR tt.description ILIKE :search_pattern OR tt.transaction_id ILIKE :search_pattern)
       AND (:status = '' OR tt.status::text = :status)
       AND (:only_unclassified = FALSE OR m.nys_snw_category_id IS NULL)
       AND (:match_state = '' OR tem.state = :match_state)
       AND (:only_unmoved_match = FALSE OR tem.match_id IS NULL OR tem.moved_to_matchy_at IS NULL)
    ORDER BY tt.date DESC, tt.transaction_id DESC
    LIMIT :limit OFFSET :offset
""")

_WRITE_TOKEN_PSA_ITEM = "_".join(("TELLER", "CLASSIFIER", "WRITE", "TOKEN"))
_WRITE_TOKEN_HEADER = "-".join(("x", "teller", "write", "token"))
_CATEGORY_TEXT_FIELDS = (
    "level_1",
    "level_1_name",
    "level_2",
    "level_2_name",
    "level_3",
    "level_4",
    "categorization",
    "applicability",
)
_CATEGORY_SCHEMA_PROPERTIES = {
    field_name: {
        "type": "string",
        "minLength": 1,
        "maxLength": 120,
        "pattern": r"^[\x20-\x7E]*[\x21-\x7E][\x20-\x7E]*$",
    }
    for field_name in _CATEGORY_TEXT_FIELDS
}
_CATEGORY_SCHEMA_REQUIRE_ONE = [{"required": [field_name]} for field_name in _CATEGORY_TEXT_FIELDS]

_MATCH_STATE_ENUM = PgEnum(
    "ai_no_match_found",
    "ai_candidate_uncertain",
    "ai_match_confident",
    "human_confirmed_ai_match",
    "human_overrode_ai_match",
    name="transaction_email_match_state",
    schema="teller",
    create_type=False,
)
_MATCH_SELECTED_BY_ENUM = PgEnum(
    "ai",
    "human",
    name="transaction_email_match_selected_by",
    schema="teller",
    create_type=False,
)
_SQL_METADATA = MetaData()
_MATCH_REVIEW_TABLE = Table(
    "transaction_email_match",
    _SQL_METADATA,
    Column("match_id", Integer),
    Column("transaction_id", String),
    Column("email_message_id", String),
    Column("state", _MATCH_STATE_ENUM),
    Column("ai_confidence", Float),
    Column("selected_by", _MATCH_SELECTED_BY_ENUM),
    Column("selected_at", DateTime(timezone=True)),
    Column("updated_at", DateTime(timezone=True)),
    Column("moved_to_matchy_at", DateTime(timezone=True)),
    Column("active", Boolean),
    schema="teller",
)
_TRANSACTION_TABLE = Table(
    "transaction",
    _SQL_METADATA,
    Column("transaction_id", String),
    Column("description", String),
    Column("amount", Numeric),
    Column("date", Date),
    schema="teller",
)


_LATEST_MATCH_RUN_SQL = text("""
    SELECT match_run_id
      FROM teller.transaction_email_match_run
     WHERE transaction_id = :transaction_id
     ORDER BY started_at DESC, match_run_id DESC
     LIMIT 1
""")

_LATEST_RUN_CANDIDATES_SQL = text("""
    SELECT candidate_id,
           email_message_id,
           score,
           reason_json,
           email_received_at,
           is_selected_by_ai,
           is_unmatched_email_priority,
           cached_subject,
           cached_sender,
           cached_snippet,
           cached_fetched_at
      FROM teller.transaction_email_candidate
     WHERE match_run_id = :match_run_id
     ORDER BY score DESC, email_received_at DESC NULLS LAST, candidate_id ASC
""")

_UPDATE_CANDIDATE_CACHE_SQL = text("""
    UPDATE teller.transaction_email_candidate
       SET cached_subject = :cached_subject,
           cached_sender = :cached_sender,
           cached_snippet = :cached_snippet,
           cached_fetched_at = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP
     WHERE candidate_id = :candidate_id
""")


def _match_review_filters(state: str, only_unmoved: bool):
    filters = [_MATCH_REVIEW_TABLE.c.active.is_(True)]
    if state:
        filters.append(cast(_MATCH_REVIEW_TABLE.c.state, String) == bindparam("state"))
    if only_unmoved:
        filters.append(_MATCH_REVIEW_TABLE.c.moved_to_matchy_at.is_(None))
    return filters
def _contains_control_characters(value: str) -> bool:
    return any(unicodedata.category(char).startswith("C") for char in value)


def _validate_text_field(field_name: str, value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    if _contains_control_characters(value):
        raise ValueError(f"{field_name} contains control or non-printable characters")
    return value


def _normalize_text(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    normalized = value.strip()
    return normalized if normalized else None


@lru_cache(maxsize=1)
def _configured_write_token() -> str:
    one_psa_path = shutil.which("1psa")
    if not one_psa_path or not os.path.isabs(one_psa_path):
        raise HTTPException(status_code=500, detail="1psa is required to resolve classifier write token")
    try:
        result = run_process(  # nosec B603
            [one_psa_path, "-p", _WRITE_TOKEN_PSA_ITEM],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=500, detail="1psa is required to resolve classifier write token") from exc
    except CalledProcessError as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Unable to resolve classifier write token from 1psa item {_WRITE_TOKEN_PSA_ITEM}",
        ) from exc
    token = result.stdout.strip()
    if not token:
        raise HTTPException(
            status_code=500,
            detail=f"1psa item {_WRITE_TOKEN_PSA_ITEM} returned an empty classifier write token",
        )
    return token


def _require_write_access(request: Request) -> None:
    #R040: Require authenticated write-token header for state-changing routes.
    candidate = request.headers.get(_WRITE_TOKEN_HEADER)
    if not candidate:
        raise HTTPException(
            status_code=401,
            detail="Missing write token header: X-Teller-Write-Token",
        )
    if candidate != _configured_write_token():
        raise HTTPException(status_code=401, detail="Invalid write token")


#R001: FastAPI app factory and route wiring for classification APIs.
class CategoryOption(BaseModel):
    nys_snw_category_id: int
    level_1: Optional[str] = None
    level_1_name: Optional[str] = None
    level_2: Optional[str] = None
    level_2_name: Optional[str] = None
    level_3: Optional[str] = None
    level_4: Optional[str] = None
    categorization: Optional[str] = None
    applicability: Optional[str] = None
    display_label: str


class CategoryMutationBase(BaseModel):
    model_config = ConfigDict(extra="forbid")
    level_1: Optional[Annotated[str, StringConstraints(max_length=120)]] = None
    level_1_name: Optional[Annotated[str, StringConstraints(max_length=120)]] = None
    level_2: Optional[Annotated[str, StringConstraints(max_length=120)]] = None
    level_2_name: Optional[Annotated[str, StringConstraints(max_length=120)]] = None
    level_3: Optional[Annotated[str, StringConstraints(max_length=120)]] = None
    level_4: Optional[Annotated[str, StringConstraints(max_length=120)]] = None
    categorization: Optional[Annotated[str, StringConstraints(max_length=120)]] = None
    applicability: Optional[Annotated[str, StringConstraints(max_length=120)]] = None

    @field_validator(*_CATEGORY_TEXT_FIELDS)
    @classmethod
    def reject_invalid_text(cls, value: Optional[str], info):
        return _validate_text_field(info.field_name, value)

    @model_validator(mode="before")
    @classmethod
    def reject_null_hierarchy_values(cls, values: Any):
        if not isinstance(values, dict):
            return values
        null_fields = [field_name for field_name in _CATEGORY_TEXT_FIELDS if field_name in values and values[field_name] is None]
        if null_fields:
            field_list = ", ".join(null_fields)
            raise ValueError(f"Null hierarchy values are not allowed: {field_list}")
        return values


class CategoryCreateMutation(CategoryMutationBase):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "minProperties": 1,
            "anyOf": _CATEGORY_SCHEMA_REQUIRE_ONE,
            "properties": _CATEGORY_SCHEMA_PROPERTIES,
        },
    )

    @model_validator(mode="after")
    def require_meaningful_content(self):
        if all(_normalize_text(getattr(self, field_name)) is None for field_name in _CATEGORY_TEXT_FIELDS):
            raise ValueError("Category create payload must include at least one non-empty hierarchy field")
        return self


class CategoryUpdateMutation(CategoryMutationBase):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "minProperties": 1,
            "anyOf": _CATEGORY_SCHEMA_REQUIRE_ONE,
            "properties": _CATEGORY_SCHEMA_PROPERTIES,
        },
    )

    @model_validator(mode="after")
    def require_at_least_one_field(self):
        if not self.model_fields_set:
            raise ValueError("Category update payload must include at least one field")
        return self

class CategoryDeleteResponse(BaseModel):
    nys_snw_category_id: int
    deleted: Literal[True] = True


class ApiError(BaseModel):
    detail: Any


class TransactionCategory(BaseModel):
    nys_snw_category_id: int
    display_label: str


class TransactionMatchInfo(BaseModel):
    #R070: Active-match summary attached to each transaction row so the unified Match & Classify UI
    #R070: can render both classification and match badges from one /v1/transactions response.
    match_id: int
    email_message_id: Optional[str] = None
    state: str
    ai_confidence: Optional[float] = None
    selected_by: str
    moved_to_matchy_at: Optional[datetime] = None
    match_count: int = 1


class TransactionRow(BaseModel):
    transaction_id: str
    account_id: str
    institution_id: Optional[str] = None
    account_last_four: Optional[str] = None
    date: date
    amount: Decimal
    description: str
    status: str
    transaction_type_code: Optional[str] = None
    teller_category: Optional[str] = None
    classification: Optional[TransactionCategory] = None
    match: Optional[TransactionMatchInfo] = None


class TransactionListResponse(BaseModel):
    total: int
    items: List[TransactionRow]


class ClassificationMutation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    transaction_id: Annotated[str, StringConstraints(min_length=1, max_length=120, pattern=r"^[A-Za-z0-9_.:-]+$")]
    nys_snw_category_id: Optional[int] = None

    @field_validator("transaction_id")
    @classmethod
    def reject_control_characters(cls, value: str):
        #R045: Enforce transaction identifier hygiene constraints.
        return _validate_text_field("transaction_id", value)


class ClassificationBatchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    updates: List[ClassificationMutation] = Field(min_length=1, max_length=250)


class SingleClassificationMutation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    nys_snw_category_id: Optional[int] = None


class ClassificationWriteResponse(BaseModel):
    transaction_id: str
    nys_snw_category_id: Optional[int] = None
    type: Literal["user"] = "user"
    updated_at: datetime


class CategoryCountsRow(BaseModel):
    nys_snw_category_id: int
    display_label: str
    assigned_transactions: int


class MatchReviewRow(BaseModel):
    match_id: int
    transaction_id: str
    email_message_id: Optional[str] = None
    state: str
    ai_confidence: Optional[float] = None
    selected_by: str
    selected_at: datetime
    moved_to_matchy_at: Optional[datetime] = None
    description: str
    amount: Decimal
    date: date


class MatchReviewListResponse(BaseModel):
    total: int
    items: List[MatchReviewRow]


class MatchReviewActionResponse(BaseModel):
    match_id: int
    transaction_id: str
    state: str
    selected_by: str
    updated_at: datetime


class MatchCandidateRow(BaseModel):
    #R060: Latest-run candidate row enriched with Mailcart metadata for the middle pane.
    email_message_id: str
    score: float
    reason_json: Dict[str, Any] = Field(default_factory=dict)
    email_received_at: Optional[datetime] = None
    is_selected_by_ai: bool = False
    is_unmatched_email_priority: bool = False
    subject: Optional[str] = None
    sender: Optional[str] = Field(default=None, alias="from")
    snippet: Optional[str] = None
    mailcart_error: Optional[str] = None

    model_config = ConfigDict(populate_by_name=True, ser_json_inf_nan="null")


class EmailMessage(BaseModel):
    #R061: Full email message body proxied from Mailcart.
    email_message_id: str
    subject: Optional[str] = None
    sender: Optional[str] = Field(default=None, alias="from")
    recipients: Optional[str] = Field(default=None, alias="to")
    received_at: Optional[datetime] = None
    html_body: Optional[str] = None
    text_body: Optional[str] = None
    snippet: Optional[str] = None

    model_config = ConfigDict(populate_by_name=True)


class EmailSearchHit(BaseModel):
    email_message_id: str
    subject: Optional[str] = None
    sender: Optional[str] = Field(default=None, alias="from")
    received_at: Optional[datetime] = None
    snippet: Optional[str] = None

    model_config = ConfigDict(populate_by_name=True)


class EmailSearchResponse(BaseModel):
    #R062: Free-form Mailcart search results proxied through the classifier API.
    query: str
    items: List[EmailSearchHit]


#R061: Microsoft Graph message IDs are URL-safe base64-ish strings (letters, digits, dashes, underscores,
#R061: and occasionally `=` padding); cap at 4096 chars to comfortably cover Graph IDs (typically ~152).
_EMAIL_MESSAGE_ID_PATTERN = r"^[A-Za-z0-9_\-=]+$"
_EMAIL_MESSAGE_ID_MAX_LENGTH = 4096
_EMAIL_SEARCH_QUERY_PATTERN = r"^[\x20-\x7E]+$"


class MatchOverrideMutation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email_message_id: Annotated[str, StringConstraints(min_length=1, max_length=400, pattern=r"^[\x20-\x7E]+$")]
    note: Optional[Annotated[str, StringConstraints(max_length=800, pattern=r"^[\x20-\x7E]*$")]] = None

    @field_validator("email_message_id")
    @classmethod
    def validate_email_message_id(cls, value: str):
        return _validate_text_field("email_message_id", value)

    @field_validator("note")
    @classmethod
    def validate_note(cls, value: Optional[str]):
        return _validate_text_field("note", value)


#R005: Build hierarchical category display labels.
def _display_label(row: Dict[str, object]) -> str:
    parts = [
        row.get("level_1_name") or row.get("level_1"),
        row.get("level_2_name") or row.get("level_2"),
        row.get("level_3"),
        row.get("level_4"),
        row.get("categorization"),
    ]
    return " > ".join(str(v).strip() for v in parts if v and str(v).strip())


#R025: Validate referenced IDs before writes.
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
    row = session.execute(text("""
        SELECT nys_snw_category_id, level_1, level_1_name, level_2, level_2_name, level_3, level_4,
               categorization, applicability, is_seed
          FROM teller.nys_snw_category
         WHERE nys_snw_category_id = :nys_snw_category_id
         LIMIT 1
    """), {"nys_snw_category_id": category_id}).mappings().fetchone()
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


def _write_category(session, body: CategoryMutationBase, category_id: Optional[int] = None) -> CategoryOption:
    try:
        if category_id is None:
            params = _category_params(body, include_unset=True)
            if all(value is None for value in params.values()):
                raise HTTPException(status_code=422, detail="Category create payload must include non-empty hierarchy text")
            created = session.execute(text("""
                INSERT INTO teller.nys_snw_category (
                    level_1, level_1_name, level_2, level_2_name, level_3, level_4, categorization, applicability
                ) VALUES (
                    :level_1, :level_1_name, :level_2, :level_2_name, :level_3, :level_4, :categorization, :applicability
                )
                RETURNING nys_snw_category_id
            """), params).fetchone()
            session.commit()
            row = _fetch_category(session, created[0])
            return _category_option_from_row(row)
        _ensure_exists(session, "nys_snw_category", "nys_snw_category_id", category_id,
                       f"Unknown nys_snw_category_id: {category_id}")
        existing = _fetch_category(session, category_id)
        if existing.get("is_seed"):
            raise HTTPException(status_code=409, detail=f"Category {category_id} is seed-protected and cannot be modified")
        patch_params = _category_params(body, include_unset=False)
        if not patch_params:
            raise HTTPException(status_code=422, detail="Category update payload must include at least one mutable field")
        merged_params = {
            "level_1": _normalize_text(existing.get("level_1")),
            "level_1_name": _normalize_text(existing.get("level_1_name")),
            "level_2": _normalize_text(existing.get("level_2")),
            "level_2_name": _normalize_text(existing.get("level_2_name")),
            "level_3": _normalize_text(existing.get("level_3")),
            "level_4": _normalize_text(existing.get("level_4")),
            "categorization": _normalize_text(existing.get("categorization")),
            "applicability": _normalize_text(existing.get("applicability")),
        }
        merged_params.update(patch_params)
        if all(value is None for value in merged_params.values()):
            raise HTTPException(status_code=409, detail="Category mutation must include at least one non-empty hierarchy field")
        params = dict(merged_params)
        params["nys_snw_category_id"] = category_id
        session.execute(text("""
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
        """), params)
        session.commit()
        row = _fetch_category(session, category_id)
        return _category_option_from_row(row)
    except HTTPException:
        raise
    except IntegrityError:
        #R050: Duplicate hierarchy writes surface as HTTP 409 conflict.
        raise HTTPException(status_code=409, detail="Category mutation conflicts with an existing hierarchy row")
    except (DataError, UnicodeEncodeError):
        raise HTTPException(status_code=422, detail="Category payload violates database constraints")
    except Exception:
        raise HTTPException(status_code=422, detail="Category payload violates database constraints")


#R025: Validate and apply transaction classification mutation.
def _write_one(session, transaction_id: str, nys_snw_category_id: Optional[int]) -> ClassificationWriteResponse:
    posted_row = session.execute(text("""
        SELECT 1
          FROM teller.transaction
         WHERE transaction_id = :transaction_id
           AND status = 'posted'
         LIMIT 1
    """), {"transaction_id": transaction_id}).fetchone()
    if not posted_row:
        raise HTTPException(status_code=404, detail=f"Unknown transaction_id: {transaction_id}")
    if nys_snw_category_id is None:
        session.execute(text("DELETE FROM teller.transaction_nys_snw_category WHERE transaction_id = :transaction_id"),
                        {"transaction_id": transaction_id})
        session.commit()
        return ClassificationWriteResponse(
            transaction_id=transaction_id,
            nys_snw_category_id=None,
            updated_at=datetime.now(timezone.utc),
        )
    _ensure_exists(session, "nys_snw_category", "nys_snw_category_id", nys_snw_category_id,
                   f"Unknown nys_snw_category_id: {nys_snw_category_id}")
    updated = session.execute(text("""
        UPDATE teller.transaction_nys_snw_category
           SET nys_snw_category_id = :nys_snw_category_id, type = 'user', updated_at = CURRENT_TIMESTAMP
         WHERE transaction_id = :transaction_id
     RETURNING updated_at
    """), {"transaction_id": transaction_id, "nys_snw_category_id": nys_snw_category_id}).fetchone()
    if not updated:
        updated = session.execute(text("""
            INSERT INTO teller.transaction_nys_snw_category (transaction_id, nys_snw_category_id, type)
            VALUES (:transaction_id, :nys_snw_category_id, 'user')
         RETURNING updated_at
        """), {"transaction_id": transaction_id, "nys_snw_category_id": nys_snw_category_id}).fetchone()
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
    row = session.execute(text("""
        SELECT m.match_id,
               m.transaction_id,
               m.email_message_id,
               m.state::text AS state,
               m.selected_by::text AS selected_by
          FROM teller.transaction_email_match m
         WHERE m.match_id = :match_id
         LIMIT 1
    """), {"match_id": match_id}).mappings().fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"Unknown match_id: {match_id}")
    return dict(row)


def _insert_match_audit(session, match_id: int, from_state: Optional[str], to_state: str, actor: str, note: Optional[str]) -> None:
    session.execute(text("""
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
    """), {
        "match_id": match_id,
        "from_state": from_state,
        "to_state": to_state,
        "actor": actor,
        "note": note,
    })


def _transition_match_state(
    session,
    match_id: int,
    to_state: str,
    actor: str,
    note: Optional[str],
    email_message_id: Optional[str] = None,
    clear_email_message_id: bool = False,
) -> MatchReviewActionResponse:
    row = _read_match_row(session, match_id)
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
        _insert_match_audit(session, match_id, row["state"], to_state, actor, note)
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


def _ensure_posted_transaction(session, transaction_id: str) -> None:
    posted_row = session.execute(text("""
        SELECT 1
          FROM teller.transaction
         WHERE transaction_id = :transaction_id
           AND status = 'posted'
         LIMIT 1
    """), {"transaction_id": transaction_id}).fetchone()
    if not posted_row:
        raise HTTPException(status_code=404, detail=f"Unknown transaction_id: {transaction_id}")


def _ensure_no_active_match(session, transaction_id: str) -> None:
    existing = session.execute(text("""
        SELECT match_id
          FROM teller.transaction_email_match
         WHERE transaction_id = :transaction_id
           AND active = TRUE
         LIMIT 1
    """), {"transaction_id": transaction_id}).fetchone()
    if existing:
        raise HTTPException(
            status_code=409,
            detail="Transaction already has an active match; use /v1/matchy/matches/{match_id} mutation endpoints",
        )


def _ensure_candidate_for_transaction(session, transaction_id: str, email_message_id: str) -> None:
    latest = session.execute(_LATEST_MATCH_RUN_SQL, {"transaction_id": transaction_id}).fetchone()
    if not latest:
        raise HTTPException(status_code=404, detail=f"No match runs recorded for transaction_id: {transaction_id}")
    candidate = session.execute(text("""
        SELECT 1
          FROM teller.transaction_email_candidate
         WHERE match_run_id = :match_run_id
           AND email_message_id = :email_message_id
         LIMIT 1
    """), {"match_run_id": latest[0], "email_message_id": email_message_id}).fetchone()
    if not candidate:
        raise HTTPException(
            status_code=422,
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
) -> MatchReviewActionResponse:
    _ensure_posted_transaction(session, transaction_id)
    _ensure_no_active_match(session, transaction_id)
    if to_state == "ai_no_match_found":
        if email_message_id is not None:
            raise HTTPException(status_code=422, detail="email_message_id must be omitted for no-email matches")
    else:
        if not email_message_id:
            raise HTTPException(status_code=422, detail="email_message_id is required")
        _validate_email_message_id(email_message_id)
        _ensure_candidate_for_transaction(session, transaction_id, email_message_id)
    try:
        inserted = session.execute(text("""
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
        """), {
            "transaction_id": transaction_id,
            "email_message_id": email_message_id,
            "state": to_state,
            "ai_confidence": ai_confidence,
            "selected_by": actor,
        }).mappings().fetchone()
        if not inserted:
            raise HTTPException(status_code=500, detail="Failed to create match row")
        match_id = int(inserted["match_id"])
        updated_at = inserted["updated_at"]
        if isinstance(updated_at, datetime) and updated_at.tzinfo is None:
            updated_at = updated_at.replace(tzinfo=timezone.utc)
        _insert_match_audit(session, match_id, None, to_state, actor, note)
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


def create_app() -> FastAPI:
    app = FastAPI(title="Teller Classification API", version="0.1.0")

    #R001: Health endpoint exposed by app factory.
    @app.get("/health")
    def health():
        return {"ok": True}

    #R010: List category options with computed display labels.
    @app.get("/v1/categories", response_model=List[CategoryOption])
    def list_categories():
        with get_session() as session:
            rows = session.execute(text("""
                SELECT nys_snw_category_id, level_1, level_1_name, level_2, level_2_name, level_3, level_4,
                       categorization, applicability
                  FROM teller.nys_snw_category
                 ORDER BY level_1, level_2, level_3, level_4, categorization, nys_snw_category_id
            """)).mappings().all()
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
        _require_write_access(request)
        with get_session() as session:
            return _write_category(session, body)

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
        _require_write_access(request)
        with get_session() as session:
            return _write_category(session, body, category_id=nys_snw_category_id)

    @app.delete("/v1/categories/{nys_snw_category_id:int}", response_model=CategoryDeleteResponse, responses={
        404: {"model": ApiError, "description": "Unknown category id"},
        409: {"model": ApiError, "description": "Category still referenced by transactions"},
    })
    def delete_category(request: Request, nys_snw_category_id: int):
        _require_write_access(request)
        with get_session() as session:
            _ensure_exists(session, "nys_snw_category", "nys_snw_category_id", nys_snw_category_id,
                           f"Unknown nys_snw_category_id: {nys_snw_category_id}")
            category_row = _fetch_category(session, nys_snw_category_id)
            if category_row.get("is_seed"):
                raise HTTPException(
                    status_code=409,
                    detail=f"Category {nys_snw_category_id} is seed-protected and cannot be deleted.",
                )
            assignment_count = session.execute(text("""
                SELECT COUNT(*)::INT
                  FROM teller.transaction_nys_snw_category
                 WHERE nys_snw_category_id = :nys_snw_category_id
            """), {"nys_snw_category_id": nys_snw_category_id}).scalar_one()
            if assignment_count > 0:
                raise HTTPException(
                    status_code=409,
                    detail=f"Cannot delete category {nys_snw_category_id}; {assignment_count} transaction(s) still reference it.",
                )
            session.execute(text("""
                DELETE FROM teller.nys_snw_category
                 WHERE nys_snw_category_id = :nys_snw_category_id
            """), {"nys_snw_category_id": nys_snw_category_id})
            session.commit()
        return CategoryDeleteResponse(nys_snw_category_id=nys_snw_category_id)

    #R015: Aggregate assignment counts including zero-assignment categories.
    @app.get("/v1/categories/counts", response_model=List[CategoryCountsRow])
    def category_counts():
        with get_session() as session:
            rows = session.execute(text("""
                SELECT c.nys_snw_category_id, c.level_1, c.level_1_name, c.level_2, c.level_2_name, c.level_3, c.level_4,
                       c.categorization, COUNT(tc.transaction_id)::INT AS assigned_transactions
                  FROM teller.nys_snw_category c
             LEFT JOIN teller.transaction_nys_snw_category tc USING (nys_snw_category_id)
              GROUP BY c.nys_snw_category_id, c.level_1, c.level_1_name, c.level_2, c.level_2_name, c.level_3, c.level_4,
                       c.categorization
              ORDER BY assigned_transactions DESC, c.level_1, c.level_2, c.level_3
            """)).mappings().all()
        return [CategoryCountsRow(nys_snw_category_id=row["nys_snw_category_id"], display_label=_display_label(row),
                                  assigned_transactions=row["assigned_transactions"]) for row in rows]

    @app.api_route("/v1/categories/counts", methods=["POST", "PUT", "PATCH", "DELETE"], include_in_schema=False)
    def category_counts_method_not_allowed():
        return Response(status_code=405, headers={"Allow": "GET"})

    #R020: Posted transaction listing with filters and latest classification context.
    @app.get("/v1/transactions", response_model=TransactionListResponse, responses={
        400: {"model": ApiError, "description": "Invalid query parameter value"},
        500: {"model": ApiError, "description": "Unexpected server error"},
    })
    def list_transactions(
        request: Request,
        search: str = Query(default="", min_length=0, max_length=120, pattern=r"^[\x20-\x7E]*$"),
        status: Literal["", "posted", "pending"] = Query(default=""),
        only_unclassified: bool = Query(default=False),
        match_state: Literal["", "ai_no_match_found", "ai_candidate_uncertain", "ai_match_confident",
                              "human_confirmed_ai_match", "human_overrode_ai_match"] = Query(default=""),
        only_unmoved_match: bool = Query(default=False),
        limit: int = Query(default=150, ge=1, le=500),
        offset: int = Query(default=0, ge=0, le=1_000_000),
    ):
        allowed_query_params = {
            "search", "status", "only_unclassified", "match_state", "only_unmoved_match", "limit", "offset",
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
        params = {
            "search": search,
            "search_pattern": f"%{search}%" if search else "",
            "status": status,
            "only_unclassified": only_unclassified,
            "match_state": match_state,
            "only_unmoved_match": only_unmoved_match,
            "limit": limit,
            "offset": offset,
        }
        try:
            with get_session() as session:
                total = session.execute(_TRANSACTION_COUNT_SQL, params).scalar_one()
                rows = session.execute(_TRANSACTION_LIST_SQL, params).mappings().all()
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
            items.append(TransactionRow(transaction_id=row["transaction_id"], account_id=row["account_id"],
                                        institution_id=row["institution_id"], account_last_four=row["account_last_four"],
                                        date=row["date"], amount=row["amount"], description=row["description"],
                                        status=row["status"], transaction_type_code=row["transaction_type_code"],
                                        teller_category=row["teller_category"], classification=classification,
                                        match=match_info))
        return TransactionListResponse(total=total, items=items)

    #R030: Use path transaction ID as the source of truth for single writes.
    @app.put("/v1/transactions/{transaction_id}/classification", response_model=ClassificationWriteResponse, responses={
        400: {"model": ApiError, "description": "Malformed request body"},
        404: {"model": ApiError, "description": "Unknown transaction or category id"},
    })
    def set_classification(request: Request, transaction_id: str, body: SingleClassificationMutation):
        _require_write_access(request)
        with get_session() as session:
            return _write_one(session, transaction_id, body.nys_snw_category_id)

    #R035: Batch classification writes require non-empty updates.
    @app.post("/v1/transactions/classifications", response_model=List[ClassificationWriteResponse], responses={
        404: {"model": ApiError, "description": "Unknown transaction or category id"},
    })
    def set_classifications(request: Request, body: ClassificationBatchRequest):
        _require_write_access(request)
        with get_session() as session:
            responses = [_write_one(session, item.transaction_id, item.nys_snw_category_id) for item in body.updates]
        return responses

    @app.get("/v1/matchy/review", response_model=MatchReviewListResponse)
    def list_matchy_review(
        state: Literal["", "ai_no_match_found", "ai_candidate_uncertain", "ai_match_confident", "human_confirmed_ai_match", "human_overrode_ai_match"] = Query(default=""),
        only_unmoved: bool = Query(default=False),
        limit: int = Query(default=100, ge=1, le=500),
        offset: int = Query(default=0, ge=0, le=1_000_000),
    ):
        filters = _match_review_filters(state=state, only_unmoved=only_unmoved)
        params: Dict[str, object] = {"limit": limit, "offset": offset}
        if state:
            params["state"] = state
        total_stmt = (
            select(func.count())
            .select_from(_MATCH_REVIEW_TABLE)
            .where(*filters)
        )
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
        with get_session() as session:
            total = session.execute(total_stmt, params).scalar_one()
            rows = session.execute(rows_stmt, params).mappings().all()
        items = [MatchReviewRow(**row) for row in rows]
        return MatchReviewListResponse(total=total, items=items)

    #R055: Document not-found parity for match-review mutation endpoints.
    @app.put(
        "/v1/matchy/matches/{match_id:int}/confirm",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown match id"},
            409: {"model": ApiError, "description": "Match state transition conflicts with current state"},
        },
    )
    def confirm_match(request: Request, match_id: int):
        _require_write_access(request)
        with get_session() as session:
            return _transition_match_state(
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
            404: {"model": ApiError, "description": "Unknown match id"},
            409: {"model": ApiError, "description": "Match state transition conflicts with current state"},
        },
    )
    def override_match(request: Request, match_id: int, body: MatchOverrideMutation):
        _require_write_access(request)
        with get_session() as session:
            return _transition_match_state(
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
        _require_write_access(request)
        with get_session() as session:
            return _transition_match_state(
                session=session,
                match_id=match_id,
                to_state="ai_no_match_found",
                actor="human",
                note="Marked no-email from Teller review UI",
                clear_email_message_id=True,
            )

    @app.put(
        "/v1/matchy/transactions/{transaction_id}/confirm-candidate",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown transaction or no match runs recorded"},
            409: {"model": ApiError, "description": "Transaction already has an active match or email link conflict"},
            422: {"model": ApiError, "description": "Selected email is not a candidate for this transaction"},
        },
    )
    def confirm_transaction_candidate(request: Request, transaction_id: str, body: MatchOverrideMutation):
        _require_write_access(request)
        with get_session() as session:
            return _create_transaction_match(
                session=session,
                transaction_id=transaction_id,
                email_message_id=body.email_message_id,
                to_state="human_confirmed_ai_match",
                actor="human",
                note=body.note or "Confirmed candidate from Teller review UI",
            )

    @app.put(
        "/v1/matchy/transactions/{transaction_id}/override-candidate",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown transaction or no match runs recorded"},
            409: {"model": ApiError, "description": "Transaction already has an active match or email link conflict"},
            422: {"model": ApiError, "description": "Selected email is not a candidate for this transaction"},
        },
    )
    def override_transaction_candidate(request: Request, transaction_id: str, body: MatchOverrideMutation):
        _require_write_access(request)
        with get_session() as session:
            return _create_transaction_match(
                session=session,
                transaction_id=transaction_id,
                email_message_id=body.email_message_id,
                to_state="human_overrode_ai_match",
                actor="human",
                note=body.note or "Overridden from Teller review UI",
            )

    @app.put(
        "/v1/matchy/transactions/{transaction_id}/no-email",
        response_model=MatchReviewActionResponse,
        responses={
            404: {"model": ApiError, "description": "Unknown transaction"},
            409: {"model": ApiError, "description": "Transaction already has an active match"},
        },
    )
    def mark_transaction_no_email(request: Request, transaction_id: str):
        _require_write_access(request)
        with get_session() as session:
            return _create_transaction_match(
                session=session,
                transaction_id=transaction_id,
                to_state="ai_no_match_found",
                actor="human",
                note="Marked no-email from Teller review UI",
            )

    #R060: List latest-run candidates for a transaction, enriched with Mailcart metadata.
    @app.get(
        "/v1/matchy/transactions/{transaction_id}/candidates",
        response_model=List[MatchCandidateRow],
        response_model_by_alias=True,
        responses={
            404: {"model": ApiError, "description": "Unknown transaction or no match runs recorded"},
            503: {"model": ApiError, "description": "Mailcart is not configured"},
        },
    )
    def list_match_candidates(transaction_id: str):
        with get_session() as session:
            latest = session.execute(_LATEST_MATCH_RUN_SQL, {"transaction_id": transaction_id}).fetchone()
            if not latest:
                raise HTTPException(status_code=404, detail=f"No match runs recorded for transaction_id: {transaction_id}")
            candidate_rows = session.execute(
                _LATEST_RUN_CANDIDATES_SQL, {"match_run_id": latest[0]}
            ).mappings().all()
            if not candidate_rows:
                return []
            return _enrich_candidates_with_mailcart(session, candidate_rows)

    #R061: Proxy the full message body + metadata from Mailcart for the right pane.
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
    def get_match_message(email_message_id: str):
        _validate_email_message_id(email_message_id)
        client = get_mailcart_client()
        try:
            payload = client.get_message(email_message_id)
        except MailcartError as exc:
            raise HTTPException(status_code=exc.status_code, detail=exc.message)
        return _email_message_from_payload(email_message_id, payload)

    #R062: Proxy a free-form Mailcart search to populate the secondary middle-pane results.
    @app.get(
        "/v1/matchy/messages/search",
        response_model=EmailSearchResponse,
        response_model_by_alias=True,
        responses={
            400: {"model": ApiError, "description": "Invalid query parameter"},
            502: {"model": ApiError, "description": "Mailcart upstream returned an unexpected response"},
            503: {"model": ApiError, "description": "Mailcart is not configured"},
        },
    )
    def search_match_messages(
        query: Annotated[str, StringConstraints(min_length=1, max_length=200, pattern=_EMAIL_SEARCH_QUERY_PATTERN)] = Query(...),
        limit: int = Query(default=25, ge=1, le=100),
    ):
        client = get_mailcart_client()
        try:
            payload = client.search(query=query, limit=limit)
        except MailcartError as exc:
            raise HTTPException(status_code=exc.status_code, detail=exc.message)
        #R062: Mailcart returns {"messages": [...]} (see mailcart/scripts/matchy_mailcart_api.py R020); accept "items"
        #R062: as a fallback so a future contract change does not silently break the UI.
        hits_raw = None
        if isinstance(payload, dict):
            hits_raw = payload.get("messages")
            if not isinstance(hits_raw, list):
                hits_raw = payload.get("items")
        if not isinstance(hits_raw, list):
            raise HTTPException(status_code=502, detail="mailcart: search response missing 'messages' array")
        hits = [_email_search_hit_from_payload(item) for item in hits_raw if isinstance(item, dict)]
        return EmailSearchResponse(query=query, items=hits)

    return app


def _validate_email_message_id(email_message_id: str) -> None:
    if (
        not email_message_id
        or len(email_message_id) > _EMAIL_MESSAGE_ID_MAX_LENGTH
        or not re.match(_EMAIL_MESSAGE_ID_PATTERN, email_message_id)
    ):
        raise HTTPException(status_code=400, detail="Invalid email_message_id")


_MAILCART_ENRICHMENT_WORKERS = 16


def _enrich_candidates_with_mailcart(session, candidate_rows: List[Dict[str, Any]]) -> List[MatchCandidateRow]:
    #R060: Best-effort fan-out enrichment; per-id Mailcart failures degrade to mailcart_error rather than 502.
    #R060: For rows that already carry cached subject/sender/snippet (matchy persists these at
    #R060: candidate-insert time), serve directly from the DB so the candidates pane is subsecond.
    #R060: For rows with NULL cache (legacy data from before the cache columns existed), fall out to
    #R060: Mailcart through a 16-worker thread pool and write the metadata back into the cache so
    #R060: the next call is hot. Order of the input candidate list is preserved in the returned list.
    if not candidate_rows:
        return []

    enriched: List[MatchCandidateRow | None] = [None] * len(candidate_rows)
    cold_indexes: List[int] = []
    for index, row in enumerate(candidate_rows):
        if row.get("cached_subject") or row.get("cached_sender") or row.get("cached_snippet"):
            enriched[index] = _candidate_row_from_cache(row)
        else:
            cold_indexes.append(index)

    if not cold_indexes:
        return [item for item in enriched if item is not None]

    try:
        client = get_mailcart_client()
    except HTTPException as exc:
        if exc.status_code == 503:
            for index in cold_indexes:
                enriched[index] = _candidate_row_with_error(candidate_rows[index], exc.detail)
            return [item for item in enriched if item is not None]
        raise

    from concurrent.futures import ThreadPoolExecutor

    def _fetch_one(index):
        row = candidate_rows[index]
        try:
            metadata = client.get_message(row["email_message_id"])
        except MailcartError as exc:
            return index, _candidate_row_with_error(row, exc.message), None
        return index, _candidate_row_from_db_and_metadata(row, metadata), metadata

    worker_count = min(_MAILCART_ENRICHMENT_WORKERS, max(1, len(cold_indexes)))
    cache_updates: List[Dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=worker_count, thread_name_prefix="mailcart-enrich") as pool:
        for index, candidate, metadata in pool.map(_fetch_one, cold_indexes):
            enriched[index] = candidate
            if metadata and isinstance(metadata, dict):
                cache_updates.append({
                    "candidate_id": candidate_rows[index]["candidate_id"],
                    "cached_subject": metadata.get("subject"),
                    "cached_sender": metadata.get("from") or metadata.get("sender"),
                    "cached_snippet": metadata.get("snippet") or metadata.get("preview") or (metadata.get("body_text") or "")[:240] or None,
                })
    # Backfill the cache so the next call is hot. Best-effort: if the write fails (e.g. read-only
    # role), log and continue rather than 500ing on the user.
    for update in cache_updates:
        try:
            session.execute(_UPDATE_CANDIDATE_CACHE_SQL, update)
        except Exception:
            session.rollback()
            break
    try:
        session.commit()
    except Exception:
        session.rollback()
    return [item for item in enriched if item is not None]


def _candidate_row_from_cache(row: Dict[str, Any]) -> MatchCandidateRow:
    payload = _candidate_payload(row)
    payload["subject"] = row.get("cached_subject")
    payload["from"] = row.get("cached_sender")
    payload["snippet"] = row.get("cached_snippet")
    return MatchCandidateRow.model_validate(payload)


def _candidate_row_from_db_and_metadata(row: Dict[str, Any], metadata: Dict[str, Any]) -> MatchCandidateRow:
    #R060: Mailcart's per-message response uses {subject, sender, preview, body_text} (and html_body for HTML
    #R060: messages); map those into the UI-facing {subject, from, snippet} fields.
    payload = _candidate_payload(row)
    if isinstance(metadata, dict):
        payload["subject"] = metadata.get("subject")
        payload["from"] = metadata.get("from") or metadata.get("sender")
        snippet = metadata.get("snippet") or metadata.get("preview")
        if not snippet:
            body_text = metadata.get("body_text") or metadata.get("text_body") or ""
            snippet = body_text[:200] if isinstance(body_text, str) else None
        payload["snippet"] = snippet or None
    return MatchCandidateRow.model_validate(payload)


def _candidate_row_with_error(row: Dict[str, Any], message: str) -> MatchCandidateRow:
    payload = _candidate_payload(row)
    payload["mailcart_error"] = message
    return MatchCandidateRow.model_validate(payload)


def _candidate_payload(row: Dict[str, Any]) -> Dict[str, Any]:
    reason = row.get("reason_json") or {}
    if not isinstance(reason, dict):
        reason = {}
    return {
        "email_message_id": row["email_message_id"],
        "score": float(row["score"]),
        "reason_json": reason,
        "email_received_at": row.get("email_received_at"),
        "is_selected_by_ai": bool(row.get("is_selected_by_ai")),
        "is_unmatched_email_priority": bool(row.get("is_unmatched_email_priority")),
    }


def _email_message_from_payload(email_message_id: str, payload: Dict[str, Any]) -> EmailMessage:
    #R061: Mailcart serializes per-message rows as {message_id, subject, sender, recipients, preview,
    #R061: html_body, text_body, body_text, received_at} (see mailcart R035); fall back to legacy
    #R061: field names where they happen to coincide so callers that mock the older contract still work.
    if not isinstance(payload, dict):
        raise HTTPException(status_code=502, detail="mailcart: message response was not a JSON object")
    return EmailMessage.model_validate({
        "email_message_id": payload.get("message_id") or payload.get("email_message_id") or email_message_id,
        "subject": payload.get("subject"),
        "from": payload.get("sender") or payload.get("from"),
        "to": payload.get("recipients") or payload.get("to"),
        "received_at": payload.get("received_at"),
        "html_body": payload.get("html_body"),
        "text_body": payload.get("text_body"),
        "snippet": payload.get("preview") or payload.get("snippet"),
    })


def _email_search_hit_from_payload(payload: Dict[str, Any]) -> EmailSearchHit:
    #R062: Mailcart search rows use {message_id, subject, sender, preview, received_at, body_text}.
    return EmailSearchHit.model_validate({
        "email_message_id": payload.get("message_id") or payload.get("email_message_id") or payload.get("id") or "",
        "subject": payload.get("subject"),
        "from": payload.get("sender") or payload.get("from"),
        "received_at": payload.get("received_at"),
        "snippet": payload.get("preview") or payload.get("snippet"),
    })
