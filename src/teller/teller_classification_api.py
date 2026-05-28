from __future__ import annotations
# ruff: noqa: F401

import sys
import hmac
import os
import shutil
from functools import lru_cache
from subprocess import CalledProcessError
from subprocess import run as run_process  # nosec B404
from fastapi import HTTPException

from teller.classification.app import (
    _register_category_routes,
    _register_health_routes,
    _register_matchy_routes,
    _register_transaction_routes,
    create_app as _create_app,
)
from teller.classification.constants import (
    _EMAIL_SEARCH_QUERY_PATTERN,
    _EXISTENCE_QUERIES,
    _LATEST_MATCH_RUN_SQL,
    _LATEST_RUN_CANDIDATES_SQL,
    _MAILCART_ENRICHMENT_WORKERS,
    _MATCH_REVIEW_TABLE,
    _TRANSACTION_COUNT_SQL,
    _TRANSACTION_LIST_SQL,
    _TRANSACTION_TABLE,
    _UPDATE_CANDIDATE_CACHE_SQL,
    _WRITE_TOKEN_HEADER,
    _WRITE_TOKEN_PSA_ITEM,
)
from teller.classification.mailcart import (
    _apply_candidate_cache_updates,
    _candidate_from_mailcart_row,
    _candidate_payload,
    _candidate_row_from_cache,
    _candidate_row_from_db_and_metadata,
    _candidate_row_with_error,
    _candidates_with_service_unavailable_error,
    _email_message_from_payload,
    _email_search_hit_from_payload,
    _enrich_candidates_with_mailcart as _enrich_candidates_with_mailcart_impl,
    _fetch_cold_candidates,
    _partition_cached_candidates,
)
from teller.classification.schemas import (
    ApiError,
    CategoryCountsRow,
    CategoryCreateMutation,
    CategoryDeleteResponse,
    CategoryMutationBase,
    CategoryOption,
    CategoryUpdateMutation,
    ClassificationBatchRequest,
    ClassificationMutation,
    ClassificationWriteResponse,
    EmailMessage,
    EmailSearchHit,
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
from teller.classification.services import (
    _category_option_from_row,
    _category_params,
    _create_category,
    _create_transaction_match as _create_transaction_match_impl,
    _create_transaction_match_allowing_non_candidate_email as _create_transaction_match_allowing_non_candidate_email_impl,
    _deactivate_match as _deactivate_match_impl,
    _ensure_candidate_for_transaction,
    _ensure_exists,
    _ensure_no_active_match,
    _ensure_posted_transaction,
    _estimate_transaction_total,
    _fetch_category,
    _insert_match_audit,
    _match_review_filters,
    _normalized_category_fields,
    _read_active_match_for_transaction,
    _read_active_match_row,
    _read_match_row,
    _transition_match_state as _transition_match_state_impl,
    _update_category,
    _write_category,
    _write_one,
)
from teller.classification.text import (
    _contains_control_characters,
    _display_label,
    _normalize_text,
    _validate_email_message_id,
    _validate_text_field,
)
from teller.teller_db import get_session
from teller.teller_mailcart_client import get_mailcart_client


#R001: Compatibility facade delegates FastAPI app factory to teller.classification.app.
#R005: Compatibility facade re-exports category display-label helper.
#R010: Compatibility facade re-exports category-list route registration bindings.
#R015: Compatibility facade re-exports category-counts route registration bindings.
#R020: Compatibility facade re-exports transaction listing SQL/service helpers.
#R025: Compatibility facade re-exports classification write validation/write helpers.
#R030: Compatibility facade re-exports single-write endpoint helper bindings.
#R035: Compatibility facade re-exports batch classification write helper bindings.
#R040: Compatibility facade preserves 1psa-backed token auth guard behavior.
#R045: Compatibility facade re-exports text validation/mutation schema helpers.
#R050: Compatibility facade re-exports category conflict-surfacing write helpers.
#R055: Compatibility facade re-exports match-review mutation helper bindings.
#R060: Compatibility facade re-exports candidate enrichment + mailcart mappings.
#R061: Compatibility facade re-exports message-body proxy payload mapping helpers.
#R062: Compatibility facade re-exports message-search proxy payload mapping helpers.
#R070: Compatibility facade re-exports active-match transaction list helpers/filters.
#R071: Compatibility facade re-exports clear/deactivate match helper bindings.
#R072: Compatibility facade re-exports include_total/count_only pagination helper.
#R073: Compatibility facade re-exports unmatched manual transaction override helper bindings.
#R075: Compatibility facade re-exports advanced transaction scalar filter support.
def _transition_match_state(*args, **kwargs):
    kwargs.setdefault("read_match_row_fn", _read_match_row)
    kwargs.setdefault("insert_match_audit_fn", _insert_match_audit)
    return _transition_match_state_impl(*args, **kwargs)


def _deactivate_match(*args, **kwargs):
    kwargs.setdefault("read_active_match_row_fn", _read_active_match_row)
    kwargs.setdefault("insert_match_audit_fn", _insert_match_audit)
    return _deactivate_match_impl(*args, **kwargs)


def _create_transaction_match(*args, **kwargs):
    kwargs.setdefault("ensure_posted_transaction_fn", _ensure_posted_transaction)
    kwargs.setdefault("ensure_no_active_match_fn", _ensure_no_active_match)
    kwargs.setdefault("ensure_candidate_for_transaction_fn", _ensure_candidate_for_transaction)
    kwargs.setdefault("insert_match_audit_fn", _insert_match_audit)
    kwargs.setdefault("validate_email_message_id_fn", _validate_email_message_id)
    return _create_transaction_match_impl(*args, **kwargs)


def _create_transaction_match_allowing_non_candidate_email(*args, **kwargs):
    #R073: Allow transaction-level override to link valid search-hit emails outside latest candidates.
    kwargs.setdefault("ensure_posted_transaction_fn", _ensure_posted_transaction)
    kwargs.setdefault("ensure_no_active_match_fn", _ensure_no_active_match)
    kwargs.setdefault("insert_match_audit_fn", _insert_match_audit)
    kwargs.setdefault("validate_email_message_id_fn", _validate_email_message_id)
    return _create_transaction_match_allowing_non_candidate_email_impl(*args, **kwargs)


def _enrich_candidates_with_mailcart(session, candidate_rows):
    return _enrich_candidates_with_mailcart_impl(
        session,
        candidate_rows,
        get_mailcart_client_fn=get_mailcart_client,
    )


def create_app():
    return _create_app(bindings=sys.modules[__name__])


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


def reset_configured_write_token_cache() -> None:
    _configured_write_token.cache_clear()


def _require_write_access(request) -> None:
    candidate = request.headers.get(_WRITE_TOKEN_HEADER)
    if not candidate:
        raise HTTPException(
            status_code=401,
            detail="Missing write token header: X-Teller-Write-Token",
        )
    if not hmac.compare_digest(candidate, _configured_write_token()):
        raise HTTPException(status_code=401, detail="Invalid write token")


def _require_authenticated_access(request) -> None:
    _require_write_access(request)
