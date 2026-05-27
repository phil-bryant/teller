from __future__ import annotations

from typing import Any, Dict, List

from fastapi import HTTPException

from teller.classification.constants import _MAILCART_ENRICHMENT_WORKERS, _UPDATE_CANDIDATE_CACHE_SQL
from teller.classification.schemas import EmailMessage, EmailSearchHit, MatchCandidateRow
from teller.teller_mailcart_client import MailcartError, get_mailcart_client


def _partition_cached_candidates(candidate_rows: List[Dict[str, Any]]) -> tuple[List[MatchCandidateRow | None], List[int]]:
    enriched: List[MatchCandidateRow | None] = [None] * len(candidate_rows)
    cold_indexes: List[int] = []
    for index, row in enumerate(candidate_rows):
        if row.get("cached_subject") or row.get("cached_sender") or row.get("cached_snippet"):
            enriched[index] = _candidate_row_from_cache(row)
        else:
            cold_indexes.append(index)
    return enriched, cold_indexes


def _candidate_from_mailcart_row(client, row: Dict[str, Any], index: int) -> tuple[int, MatchCandidateRow, Dict[str, Any] | None]:
    try:
        metadata = client.get_message(row["email_message_id"])
    except MailcartError as exc:
        if exc.status_code == 404:
            return index, _candidate_row_with_error(row, "email no longer in inbox"), {"_negative": True}
        return index, _candidate_row_with_error(row, exc.message), None
    return index, _candidate_row_from_db_and_metadata(row, metadata), metadata


def _fetch_cold_candidates(client, candidate_rows: List[Dict[str, Any]], cold_indexes: List[int]) -> tuple[List[MatchCandidateRow | None], List[Dict[str, Any]]]:
    from concurrent.futures import ThreadPoolExecutor

    cold_results: List[MatchCandidateRow | None] = [None] * len(candidate_rows)
    cache_updates: List[Dict[str, Any]] = []

    def _fetch_one(index: int):
        return _candidate_from_mailcart_row(client, candidate_rows[index], index)

    worker_count = min(_MAILCART_ENRICHMENT_WORKERS, max(1, len(cold_indexes)))
    with ThreadPoolExecutor(max_workers=worker_count, thread_name_prefix="mailcart-enrich") as pool:
        for index, candidate, metadata in pool.map(_fetch_one, cold_indexes):
            cold_results[index] = candidate
            if metadata and isinstance(metadata, dict):
                if metadata.get("_negative"):
                    cache_updates.append(
                        {
                            "candidate_id": candidate_rows[index]["candidate_id"],
                            "cached_subject": "[email no longer in inbox]",
                            "cached_sender": "",
                            "cached_snippet": None,
                        }
                    )
                else:
                    cache_updates.append(
                        {
                            "candidate_id": candidate_rows[index]["candidate_id"],
                            "cached_subject": metadata.get("subject"),
                            "cached_sender": metadata.get("from") or metadata.get("sender"),
                            "cached_snippet": metadata.get("snippet")
                            or metadata.get("preview")
                            or (metadata.get("body_text") or "")[:240]
                            or None,
                        }
                    )
    return cold_results, cache_updates


def _apply_candidate_cache_updates(session, cache_updates: List[Dict[str, Any]]) -> None:
    for cache_update in cache_updates:
        try:
            session.execute(_UPDATE_CANDIDATE_CACHE_SQL, cache_update)
        except Exception:
            session.rollback()
            break
    try:
        session.commit()
    except Exception:
        session.rollback()


def _candidates_with_service_unavailable_error(
    candidate_rows: List[Dict[str, Any]],
    cold_indexes: List[int],
    detail: str,
    enriched: List[MatchCandidateRow | None],
) -> List[MatchCandidateRow]:
    for index in cold_indexes:
        enriched[index] = _candidate_row_with_error(candidate_rows[index], detail)
    return [item for item in enriched if item is not None]


def _enrich_candidates_with_mailcart(
    session,
    candidate_rows: List[Dict[str, Any]],
    *,
    get_mailcart_client_fn=get_mailcart_client,
) -> List[MatchCandidateRow]:
    if not candidate_rows:
        return []

    enriched, cold_indexes = _partition_cached_candidates(candidate_rows)
    if not cold_indexes:
        return [item for item in enriched if item is not None]

    try:
        client = get_mailcart_client_fn()
    except HTTPException as exc:
        if exc.status_code == 503:
            return _candidates_with_service_unavailable_error(candidate_rows, cold_indexes, exc.detail, enriched)
        raise

    cold_results, cache_updates = _fetch_cold_candidates(client, candidate_rows, cold_indexes)
    for index in cold_indexes:
        enriched[index] = cold_results[index]
    _apply_candidate_cache_updates(session, cache_updates)
    return [item for item in enriched if item is not None]


def _candidate_row_from_cache(row: Dict[str, Any]) -> MatchCandidateRow:
    payload = _candidate_payload(row)
    payload["subject"] = row.get("cached_subject")
    payload["from"] = row.get("cached_sender")
    payload["snippet"] = row.get("cached_snippet")
    return MatchCandidateRow.model_validate(payload)


def _candidate_row_from_db_and_metadata(row: Dict[str, Any], metadata: Dict[str, Any]) -> MatchCandidateRow:
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
    if not isinstance(payload, dict):
        raise HTTPException(status_code=502, detail="mailcart: message response was not a JSON object")
    return EmailMessage.model_validate(
        {
            "email_message_id": payload.get("message_id") or payload.get("email_message_id") or email_message_id,
            "subject": payload.get("subject"),
            "from": payload.get("sender") or payload.get("from"),
            "to": payload.get("recipients") or payload.get("to"),
            "received_at": payload.get("received_at"),
            "html_body": payload.get("html_body"),
            "text_body": payload.get("text_body"),
            "snippet": payload.get("preview") or payload.get("snippet"),
        }
    )


def _email_search_hit_from_payload(payload: Dict[str, Any]) -> EmailSearchHit:
    return EmailSearchHit.model_validate(
        {
            "email_message_id": payload.get("message_id") or payload.get("email_message_id") or payload.get("id") or "",
            "subject": payload.get("subject"),
            "from": payload.get("sender") or payload.get("from"),
            "received_at": payload.get("received_at"),
            "snippet": payload.get("preview") or payload.get("snippet"),
        }
    )
