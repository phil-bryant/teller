from hypothesis import given, settings, strategies as st

from teller.teller_persist import _canonicalize_transactions


@st.composite
def txn_rows(draw):
    #R001: Cover traceability for this helper/test behavior.
    txn_id = draw(st.text(min_size=1, max_size=16))
    status = draw(st.sampled_from(["posted", "pending", "archived"]))
    return {"id": txn_id, "status": status}


@given(st.lists(txn_rows(), min_size=0, max_size=80))
@settings(max_examples=500, deadline=None, derandomize=True)
def test_canonicalize_transactions_produces_unique_ids(rows):
    #R001: Cover traceability for this helper/test behavior.
    canonical = _canonicalize_transactions(rows)
    ids = [row["id"] for row in canonical]
    assert len(ids) == len(set(ids))


@given(st.lists(txn_rows(), min_size=1, max_size=120))
@settings(max_examples=500, deadline=None, derandomize=True)
def test_canonicalize_transactions_prefers_posted_status(rows):
    #R001: Cover traceability for this helper/test behavior.
    canonical = _canonicalize_transactions(rows)
    canonical_by_id = {row["id"]: row["status"] for row in canonical}
    source_by_id = {}
    for row in rows:
        source_by_id.setdefault(row["id"], set()).add(row["status"])

    for txn_id, source_statuses in source_by_id.items():
        if "posted" in source_statuses:
            assert canonical_by_id[txn_id] == "posted"
