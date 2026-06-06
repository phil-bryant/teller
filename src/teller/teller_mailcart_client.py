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
    #R600: Initialize typed MailcartError status/message payload.
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.message = message


class MailcartClient:
    #R600: Build Mailcart client instances with validated HTTPS base URL defaults.
    #R600: Initialize typed MailcartError status/message payload.
    def __init__(
        self,
        base_url: str,
        token: Optional[str] = None,
        *,
        timeout_seconds: float = _DEFAULT_TIMEOUT_SECONDS,
        session: Optional[requests.Session] = None,
        max_connections: int = 32,
    ) -> None:
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

    #R625: Attach bearer token header when configured for outbound requests.
    #R630: Map upstream HTTP 429 responses to contextual gateway failures.
    #R635: Convert request transport exceptions into typed gateway failures.
    #R640: Reject success responses that are not valid JSON payloads.
    #R645: Surface bounded preview text for upstream error responses.
    #R650: Map upstream 404 responses to typed not-found Mailcart errors.
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

    #R625: Fetch Mailcart message payload through shared request pipeline.
    def get_message(self, email_message_id: str) -> Dict[str, Any]:
        return self._request("GET", f"/v1/messages/{email_message_id}")

    #R625: Search Mailcart messages through shared request pipeline.
    def search(self, query: str, limit: int) -> Dict[str, Any]:
        return self._request("GET", "/v1/messages/search", params={"query": query, "limit": limit})


@lru_cache(maxsize=8)
#R610: Cache Mailcart clients by normalized base URL and token settings.
def _mailcart_client_for_config(base_url: str, token: str) -> MailcartClient:
    return MailcartClient(base_url=base_url, token=token or None)


#R600: Build default Mailcart client configuration with cache-backed reuse.
#R605: Honor environment overrides for Mailcart base URL and token.
#R620: Reject insecure base URL values provided through environment settings.
def get_mailcart_client() -> MailcartClient:
    base_url = (os.environ.get(_BASE_URL_ENV) or _DEFAULT_BASE_URL).strip() or _DEFAULT_BASE_URL
    token = (os.environ.get(_TOKEN_ENV) or "").strip()
    normalized_base_url = _validated_https_base_url(base_url)
    return _mailcart_client_for_config(normalized_base_url, token)


#R600: Reset cached Mailcart clients for deterministic runtime/test rebuilds.
def reset_mailcart_client_cache() -> None:
    _mailcart_client_for_config.cache_clear()


#R615: Reject explicit non-HTTPS Mailcart base URL configuration.
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


#R600: Detect loopback hosts for local HTTPS certificate handling.
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
