from __future__ import annotations

import string

import pytest
from hypothesis import HealthCheck, assume, given, settings, strategies as st
from pydantic import ValidationError
from fastapi import HTTPException

from teller.teller_classification_api import (
    CategoryCreateMutation,
    _category_params,
    _display_label,
    _normalize_text,
    _validate_email_message_id,
)


_CATEGORY_FIELDS = (
    "level_1",
    "level_1_name",
    "level_2",
    "level_2_name",
    "level_3",
    "level_4",
    "categorization",
    "applicability",
)

_MAYBE_TEXT = st.one_of(st.none(), st.text(min_size=0, max_size=120))
_VISIBLE_ASCII_TEXT = st.text(alphabet=st.characters(min_codepoint=32, max_codepoint=126), min_size=0, max_size=120)


@given(st.none() | st.text())
def test_normalize_text_trims_and_none_for_blank(value):
    normalized = _normalize_text(value)
    if value is None:
        assert normalized is None
        return
    stripped = value.strip()
    if stripped == "":
        assert normalized is None
    else:
        assert normalized == stripped


@given(st.none() | st.text())
def test_normalize_text_is_idempotent(value):
    once = _normalize_text(value)
    twice = _normalize_text(once)
    assert once == twice


@given(
    level_1=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_1_name=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_2=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_2_name=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_3=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_4=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    categorization=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
)
def test_display_label_never_emits_empty_segments(
    level_1,
    level_1_name,
    level_2,
    level_2_name,
    level_3,
    level_4,
    categorization,
):
    row = {
        "level_1": level_1,
        "level_1_name": level_1_name,
        "level_2": level_2,
        "level_2_name": level_2_name,
        "level_3": level_3,
        "level_4": level_4,
        "categorization": categorization,
    }
    label = _display_label(row)
    assert " >  > " not in label
    assert not label.startswith(" > ")
    assert not label.endswith(" > ")


@given(st.fixed_dictionaries({field_name: _MAYBE_TEXT for field_name in _CATEGORY_FIELDS}))
def test_category_params_matches_normalized_field_values(raw_values):
    body = CategoryCreateMutation.model_construct(**raw_values)
    params = _category_params(body, include_unset=True)
    assert set(params.keys()) == set(_CATEGORY_FIELDS)
    for field_name in _CATEGORY_FIELDS:
        expected = _normalize_text(raw_values[field_name])
        assert params[field_name] == expected


@given(
    st.dictionaries(
        keys=st.sampled_from(_CATEGORY_FIELDS),
        values=_VISIBLE_ASCII_TEXT,
        max_size=len(_CATEGORY_FIELDS),
    )
)
def test_category_create_requires_meaningful_content(raw_values):
    has_meaningful_field = any(_normalize_text(value) is not None for value in raw_values.values())
    if has_meaningful_field:
        model = CategoryCreateMutation(**raw_values)
        assert any(_normalize_text(getattr(model, field_name)) is not None for field_name in _CATEGORY_FIELDS)
        return
    with pytest.raises(ValidationError):
        CategoryCreateMutation(**raw_values)


@given(st.text(alphabet=string.ascii_letters + string.digits + "_-=", min_size=1, max_size=200))
def test_validate_email_message_id_accepts_allowed_pattern(value):
    _validate_email_message_id(value)


@given(st.text(min_size=1, max_size=40))
def test_validate_email_message_id_rejects_disallowed_pattern(value):
    assume(any(char not in (string.ascii_letters + string.digits + "_-=") for char in value))
    with pytest.raises(HTTPException) as exc:
        _validate_email_message_id(value)
    assert exc.value.status_code == 400


@settings(suppress_health_check=[HealthCheck.large_base_example])
@given(st.text(alphabet=string.ascii_letters + string.digits + "_-=", min_size=4097, max_size=4200))
def test_validate_email_message_id_rejects_overlength_values(value):
    with pytest.raises(HTTPException) as exc:
        _validate_email_message_id(value)
    assert exc.value.status_code == 400
