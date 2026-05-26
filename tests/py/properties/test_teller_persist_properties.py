from __future__ import annotations

from hypothesis import given, strategies as st

from teller.teller_persist import _canonicalize_transactions


_STATUS = st.sampled_from(["pending", "posted"])


@given(
    st.lists(
        st.fixed_dictionaries(
            {
                "id": st.text(min_size=1, max_size=12),
                "status": _STATUS,
                "description": st.text(min_size=0, max_size=30),
            }
        ),
        min_size=0,
        max_size=80,
    )
)
def test_canonicalize_transactions_never_expands_unique_ids(txns):
    canonical = _canonicalize_transactions(txns)
    input_ids = {txn["id"] for txn in txns}
    output_ids = {txn["id"] for txn in canonical}
    assert len(canonical) <= len(input_ids)
    assert output_ids.issubset(input_ids)


@given(
    st.lists(
        st.fixed_dictionaries(
            {
                "id": st.text(min_size=1, max_size=8),
                "status": _STATUS,
                "description": st.text(min_size=0, max_size=25),
            }
        ),
        min_size=0,
        max_size=60,
    )
)
def test_canonicalize_transactions_is_idempotent(txns):
    once = _canonicalize_transactions(txns)
    twice = _canonicalize_transactions(once)
    assert twice == once


@given(
    st.lists(
        st.fixed_dictionaries(
            {
                "id": st.text(min_size=1, max_size=6),
                "status": _STATUS,
                "description": st.text(min_size=0, max_size=20),
            }
        ),
        min_size=1,
        max_size=50,
    )
)
def test_canonicalize_prefers_posted_when_any_variant_is_posted(txns):
    canonical = _canonicalize_transactions(txns)
    canonical_by_id = {txn["id"]: txn for txn in canonical}
    input_by_id = {}
    for txn in txns:
        input_by_id.setdefault(txn["id"], []).append(txn)

    for txn_id, variants in input_by_id.items():
        if any(variant["status"] == "posted" for variant in variants):
            assert canonical_by_id[txn_id]["status"] == "posted"
