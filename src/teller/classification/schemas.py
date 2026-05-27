from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

from teller.classification.constants import (
    _CATEGORY_SCHEMA_PROPERTIES,
    _CATEGORY_SCHEMA_REQUIRE_ONE,
    _CATEGORY_TEXT_FIELDS,
)
from teller.classification.text import _normalize_text, _validate_text_field


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
    query: str
    items: List[EmailSearchHit]


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
