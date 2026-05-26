from hypothesis import given, settings, strategies as st

from teller.teller_classification_api import _match_review_filters


@given(
    state=st.sampled_from(
        [
            "",
            "ai_no_match_found",
            "ai_candidate_uncertain",
            "ai_match_confident",
            "human_confirmed_ai_match",
            "human_overrode_ai_match",
        ]
    ),
    only_unmoved=st.booleans(),
)
@settings(max_examples=40, deadline=None, derandomize=True)
def test_match_review_filters_has_expected_filter_count(state, only_unmoved):
    filters = _match_review_filters(state=state, only_unmoved=only_unmoved)
    expected = 1 + (1 if state else 0) + (1 if only_unmoved else 0)
    assert len(filters) == expected
from hypothesis import given, settings, strategies as st



@given(
    state=st.sampled_from(
        [
            "",
            "ai_no_match_found",
            "ai_candidate_uncertain",
            "ai_match_confident",
            "human_confirmed_ai_match",
            "human_overrode_ai_match",
        ]
    ),
    only_unmoved=st.booleans(),
)
@settings(max_examples=40, deadline=None, derandomize=True)
def test_match_review_filters_has_expected_filter_count(state, only_unmoved):
    filters = _match_review_filters(state=state, only_unmoved=only_unmoved)
    expected = 1 + (1 if state else 0) + (1 if only_unmoved else 0)
    assert len(filters) == expected
