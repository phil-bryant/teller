from __future__ import annotations
import os
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

_EXISTENCE_QUERIES = {
    ("nys_snw_category", "nys_snw_category_id"): text("""
        SELECT 1
          FROM teller.nys_snw_category
         WHERE nys_snw_category_id = :value
         LIMIT 1
    """),
}

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
     WHERE tt.status = 'posted'
       AND (:search = '' OR tt.description ILIKE :search_pattern OR tt.transaction_id ILIKE :search_pattern)
       AND (:status = '' OR tt.status::text = :status)
       AND (:only_unclassified = FALSE OR m.nys_snw_category_id IS NULL)
""")

_TRANSACTION_LIST_SQL = text("""
    SELECT tt.transaction_id, tt.account_id, ta.institution_id, ta.last_four AS account_last_four,
           tt.date, tt.amount, tt.description, tt.status,
           ttt.code AS transaction_type_code, ttd.category AS teller_category,
           m.nys_snw_category_id, nsc.level_1, nsc.level_1_name, nsc.level_2, nsc.level_2_name,
           nsc.level_3, nsc.level_4, nsc.categorization
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
     WHERE tt.status = 'posted'
       AND (:search = '' OR tt.description ILIKE :search_pattern OR tt.transaction_id ILIKE :search_pattern)
       AND (:status = '' OR tt.status::text = :status)
       AND (:only_unclassified = FALSE OR m.nys_snw_category_id IS NULL)
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
        "maxLength": 120,
        "pattern": r"^[^\x00-\x1F\x7F]*$",
    }
    for field_name in _CATEGORY_TEXT_FIELDS
}

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


class MatchOverrideMutation(BaseModel):
    email_message_id: Annotated[str, StringConstraints(min_length=1, max_length=400)]
    note: Optional[Annotated[str, StringConstraints(max_length=800)]] = None


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
        "match_id": match_id,
        "to_state": to_state,
        "actor": actor,
    }
    if email_message_id is not None:
        params["email_message_id"] = email_message_id
    statement = (
        update(_MATCH_REVIEW_TABLE)
        .where(_MATCH_REVIEW_TABLE.c.match_id == bindparam("match_id"))
        .values(**values)
        .returning(
            _MATCH_REVIEW_TABLE.c.transaction_id,
            cast(_MATCH_REVIEW_TABLE.c.state, String).label("state"),
            cast(_MATCH_REVIEW_TABLE.c.selected_by, String).label("selected_by"),
            _MATCH_REVIEW_TABLE.c.updated_at,
        )
    )
    updated = session.execute(statement, params).mappings().fetchone()
    _insert_match_audit(session, match_id, row["state"], to_state, actor, note)
    session.commit()
    return MatchReviewActionResponse(
        match_id=match_id,
        transaction_id=updated["transaction_id"],
        state=updated["state"],
        selected_by=updated["selected_by"],
        updated_at=updated["updated_at"],
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

    @app.post("/v1/categories", response_model=CategoryOption, responses={
        400: {"model": ApiError, "description": "Invalid category payload"},
        422: {"model": ApiError, "description": "Malformed category payload"},
        409: {"model": ApiError, "description": "Category hierarchy conflicts with existing row"},
    })
    def create_category(request: Request, body: CategoryCreateMutation):
        _require_write_access(request)
        with get_session() as session:
            return _write_category(session, body)

    @app.put("/v1/categories/{nys_snw_category_id:int}", response_model=CategoryOption, responses={
        400: {"model": ApiError, "description": "Invalid category payload"},
        422: {"model": ApiError, "description": "Malformed category payload"},
        409: {"model": ApiError, "description": "Category hierarchy conflicts with existing row"},
        404: {"model": ApiError, "description": "Unknown category id"},
    })
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
        limit: int = Query(default=150, ge=1, le=500),
        offset: int = Query(default=0, ge=0, le=1_000_000),
    ):
        allowed_query_params = {"search", "status", "only_unclassified", "limit", "offset"}
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
            items.append(TransactionRow(transaction_id=row["transaction_id"], account_id=row["account_id"],
                                        institution_id=row["institution_id"], account_last_four=row["account_last_four"],
                                        date=row["date"], amount=row["amount"], description=row["description"],
                                        status=row["status"], transaction_type_code=row["transaction_type_code"],
                                        teller_category=row["teller_category"], classification=classification))
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

    @app.put("/v1/matchy/matches/{match_id:int}/confirm", response_model=MatchReviewActionResponse)
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

    @app.put("/v1/matchy/matches/{match_id:int}/override", response_model=MatchReviewActionResponse)
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

    @app.put("/v1/matchy/matches/{match_id:int}/no-email", response_model=MatchReviewActionResponse)
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

    return app
