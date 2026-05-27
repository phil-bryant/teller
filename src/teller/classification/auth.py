from __future__ import annotations

import hmac
import os
import shutil
from functools import lru_cache
from subprocess import CalledProcessError, run as run_process  # nosec B404

from fastapi import HTTPException, Request

from teller.classification.constants import _WRITE_TOKEN_HEADER, _WRITE_TOKEN_PSA_ITEM


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


def _require_write_access(request: Request) -> None:
    candidate = request.headers.get(_WRITE_TOKEN_HEADER)
    if not candidate:
        raise HTTPException(
            status_code=401,
            detail="Missing write token header: X-Teller-Write-Token",
        )
    if not hmac.compare_digest(candidate, _configured_write_token()):
        raise HTTPException(status_code=401, detail="Invalid write token")


def _require_authenticated_access(request: Request) -> None:
    _require_write_access(request)
