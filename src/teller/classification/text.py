from __future__ import annotations

import re
import unicodedata
from typing import Dict, Optional

from fastapi import HTTPException

from teller.classification.constants import _EMAIL_MESSAGE_ID_MAX_LENGTH, _EMAIL_MESSAGE_ID_PATTERN


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


def _display_label(row: Dict[str, object]) -> str:
    parts = [
        row.get("level_1_name") or row.get("level_1"),
        row.get("level_2_name") or row.get("level_2"),
        row.get("level_3"),
        row.get("level_4"),
        row.get("categorization"),
    ]
    return " > ".join(str(v).strip() for v in parts if v and str(v).strip())


def _validate_email_message_id(email_message_id: str) -> None:
    if (
        not email_message_id
        or len(email_message_id) > _EMAIL_MESSAGE_ID_MAX_LENGTH
        or not re.match(_EMAIL_MESSAGE_ID_PATTERN, email_message_id)
    ):
        raise HTTPException(status_code=400, detail="Invalid email_message_id")
