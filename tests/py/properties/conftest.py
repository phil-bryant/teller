from __future__ import annotations

import os
from datetime import timedelta
from pathlib import Path

from hypothesis import settings
from hypothesis.database import DirectoryBasedExampleDatabase


def _int_from_env(name: str, default: int) -> int:
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    try:
        value = int(raw_value)
    except ValueError:
        return default
    return value if value > 0 else default


def _deadline_from_env() -> timedelta | None:
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
    max_examples = _int_from_env("HYPOTHESIS_MAX_EXAMPLES", 100)
    deadline = _deadline_from_env()
    storage_path = os.environ.get("HYPOTHESIS_STORAGE_DIRECTORY")

    kwargs: dict[str, object] = {
        "max_examples": max_examples,
        "deadline": deadline,
    }
    if storage_path:
        kwargs["database"] = DirectoryBasedExampleDatabase(str(Path(storage_path)))

    settings.register_profile("teller_fuzz", **kwargs)
    settings.load_profile("teller_fuzz")


_load_teller_fuzz_profile()
