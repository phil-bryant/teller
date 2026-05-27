from __future__ import annotations
import os
from functools import lru_cache
from ipaddress import ip_address
from typing import Any, Dict, Optional
from urllib.parse import urlsplit

import requests
import structlog

log = structlog.get_logger()

_BASE_URL_ENV = "MAILCART_SERVICE_BASE_URL"
_TOKEN_ENV = "MAILCART_SERVICE_TOKEN"
_DEFAULT_BASE_URL = "https://127.0.0.1:8788"
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
        self._base_url = _validated_https_base_url(base_url).rstrip("/")
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
        parsed = urlsplit(self._base_url)
        if (parsed.scheme or "").lower() == "https" and _is_loopback_host(parsed.hostname):
            # Local Mailcart HTTPS commonly uses a self-signed cert in development.
            # Keep transport encrypted while allowing local loopback certs.
            session.verify = False
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
    normalized_base_url = _validated_https_base_url(base_url)
    return _mailcart_client_for_config(normalized_base_url, token)


def reset_mailcart_client_cache() -> None:
    #R060: Allow tests to drop cached clients without monkeypatching internals.
    _mailcart_client_for_config.cache_clear()


def _validated_https_base_url(base_url: str) -> str:
    normalized = (base_url or "").strip()
    if not normalized:
        raise MailcartError(status_code=503, message=f"mailcart: {_BASE_URL_ENV} must be configured with an https URL")
    parsed = urlsplit(normalized)
    scheme = (parsed.scheme or "").lower()
    if scheme != "https":
        raise MailcartError(
            status_code=503,
            message=f"mailcart: {_BASE_URL_ENV} must use https (received: {normalized})",
        )
    if not parsed.netloc:
        raise MailcartError(status_code=503, message=f"mailcart: {_BASE_URL_ENV} must include a host")
    return normalized


def _is_loopback_host(host: str | None) -> bool:
    normalized = (host or "").strip().lower()
    if normalized in {"localhost", "127.0.0.1", "::1"}:
        return True
    if not normalized:
        return False
    try:
        return ip_address(normalized).is_loopback
    except ValueError:
        return False
