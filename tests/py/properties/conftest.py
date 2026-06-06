from __future__ import annotations

import os
from datetime import timedelta
from pathlib import Path

from hypothesis import settings
from hypothesis.database import DirectoryBasedExampleDatabase

_REPO_ROOT = Path(__file__).resolve().parents[3]
_DEFAULT_HYPOTHESIS_STORAGE = _REPO_ROOT / "artifacts" / "cache" / "hypothesis"


def _hypothesis_storage_directory() -> Path:
    #R001: Cover traceability for this helper/test behavior.
    raw_value = os.environ.get("HYPOTHESIS_STORAGE_DIRECTORY")
    if raw_value:
        return Path(raw_value)
    return _DEFAULT_HYPOTHESIS_STORAGE


def _int_from_env(name: str, default: int) -> int:
    #R001: Cover traceability for this helper/test behavior.
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    try:
        value = int(raw_value)
    except ValueError:
        return default
    return value if value > 0 else default


def _deadline_from_env() -> timedelta | None:
    #R001: Cover traceability for this helper/test behavior.
    raw_value = os.environ.get("HYPOTHESIS_DEADLINE")
    if raw_value is None:
        return None
    try:
        deadline_ms = int(raw_value)
    except ValueError:
        return None
    if deadline_ms <= 0:
        return None
    return timedelta(milliseconds=deadline_ms)


def _load_teller_fuzz_profile() -> None:
    #R001: Cover traceability for this helper/test behavior.
    max_examples = _int_from_env("HYPOTHESIS_MAX_EXAMPLES", 100)
    deadline = _deadline_from_env()
    storage_path = _hypothesis_storage_directory()
    storage_path.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("HYPOTHESIS_STORAGE_DIRECTORY", str(storage_path))

    kwargs: dict[str, object] = {
        "max_examples": max_examples,
        "deadline": deadline,
        "database": DirectoryBasedExampleDatabase(str(storage_path)),
    }

    settings.register_profile("teller_fuzz", **kwargs)
    settings.load_profile("teller_fuzz")


_load_teller_fuzz_profile()
