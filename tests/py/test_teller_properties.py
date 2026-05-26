from hypothesis import given, settings, strategies as st

from teller.teller_classification_api import _display_label, _normalize_text


@given(st.none() | st.text())
@settings(max_examples=50, deadline=None, derandomize=True)
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


@given(
    level_1=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_1_name=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_2=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_2_name=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_3=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    level_4=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    categorization=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
)
@settings(max_examples=50, deadline=None, derandomize=True)
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


@given(st.none() | st.text())
@settings(max_examples=50, deadline=None, derandomize=True)
def test_normalize_text_is_idempotent(value):
    normalized = _normalize_text(value)
    assert _normalize_text(normalized) == normalized
