"""Pytest hooks for the teller Python test tree."""

from __future__ import annotations

import os
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_HYPOTHESIS_STORAGE = _REPO_ROOT / "artifacts" / "cache" / "hypothesis"

# Set before property tests import hypothesis (conftest load order is parent-first).
os.environ.setdefault("HYPOTHESIS_STORAGE_DIRECTORY", str(_DEFAULT_HYPOTHESIS_STORAGE))
_DEFAULT_HYPOTHESIS_STORAGE.mkdir(parents=True, exist_ok=True)
