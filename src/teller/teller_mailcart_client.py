from __future__ import annotations
import os
from functools import lru_cache
from typing import Any, Dict, Optional
from urllib.parse import urlsplit

import requests
import structlog

log = structlog.get_logger()

_BASE_URL_ENV = "MAILCART_SERVICE_BASE_URL"
_TOKEN_ENV = "MAILCART_SERVICE_TOKEN"
_DEFAULT_BASE_URL = "http://127.0.0.1:8788"
_DEFAULT_TIMEOUT_SECONDS = 12.0


class MailcartError(Exception):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.message = message


class MailcartClient:
    #R060: Sync HTTP client for Mailcart; contract in Architecture.md § Teller ↔ Mailcart contract.
    def __init__(self, base_url: str, token: Optional[str] = None, *, timeout_seconds: float = _DEFAULT_TIMEOUT_SECONDS,
                 session: Optional[requests.Session] = None, max_connections: int = 32) -> None:
        self._base_url = base_url.rstrip("/")
        self._token = (token or "").strip()
        self._timeout = timeout_seconds
        if session is None:
            session = requests.Session()
            # requests.Session defaults to a 10-connection pool per host, which silently throttles
            # the per-candidate ThreadPoolExecutor fan-out down to ~10x effective concurrency. Bump
            # both pool dimensions so the 16-worker enrichment actually runs 16-wide.
            adapter = requests.adapters.HTTPAdapter(
                pool_connections=max(max_connections, 4),
                pool_maxsize=max(max_connections, 4),
                max_retries=0,
            )
            scheme = (urlsplit(self._base_url).scheme or "http").lower()
            session.mount(f"{scheme}://", adapter)
        self._session = session

    def _request(self, method: str, path: str, *, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        url = f"{self._base_url}{path}"
        headers = {"Accept": "application/json"}
        if self._token:
            headers["Authorization"] = f"Bearer {self._token}"
        try:
            response = self._session.request(
                method=method,
                url=url,
                params=params,
                headers=headers,
                timeout=self._timeout,
            )
        except requests.RequestException as exc:
            raise MailcartError(status_code=502, message=f"mailcart: request failed: {exc}") from exc
        if 200 <= response.status_code < 300:
            try:
                return response.json()
            except ValueError as exc:
                raise MailcartError(status_code=502, message="mailcart: response was not valid JSON") from exc
        if response.status_code == 404:
            raise MailcartError(status_code=404, message="mailcart: message not found")
        body_preview = (response.text or "")[:200].replace("\n", " ")
        raise MailcartError(
            status_code=502,
            message=f"mailcart: upstream returned {response.status_code}: {body_preview}".strip(),
        )

    #R061: GET /v1/messages/{id}; response shape in Architecture.md § Teller ↔ Mailcart contract.
    def get_message(self, email_message_id: str) -> Dict[str, Any]:
        return self._request("GET", f"/v1/messages/{email_message_id}")

    #R060: GET /v1/messages/search; limit bounds in Architecture.md § Teller ↔ Mailcart contract.
    def search(self, query: str, limit: int) -> Dict[str, Any]:
        return self._request("GET", "/v1/messages/search", params={"query": query, "limit": limit})


@lru_cache(maxsize=8)
def _mailcart_client_for_config(base_url: str, token: str) -> MailcartClient:
    return MailcartClient(base_url=base_url, token=token or None)


def get_mailcart_client() -> MailcartClient:
    base_url = (os.environ.get(_BASE_URL_ENV) or _DEFAULT_BASE_URL).strip() or _DEFAULT_BASE_URL
    token = (os.environ.get(_TOKEN_ENV) or "").strip()
    return _mailcart_client_for_config(base_url, token)


def reset_mailcart_client_cache() -> None:
    #R060: Allow tests to drop cached clients without monkeypatching internals.
    _mailcart_client_for_config.cache_clear()
