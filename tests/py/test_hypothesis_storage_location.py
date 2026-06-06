from __future__ import annotations

import os
from pathlib import Path


def test_hypothesis_storage_directory_lives_under_artifacts_cache() -> None:
    #R001: Cover traceability for this helper/test behavior.
    storage = os.environ.get("HYPOTHESIS_STORAGE_DIRECTORY")
    assert storage is not None
    path = Path(storage)
    assert path.name == "hypothesis"
    assert path.parent.name == "cache"
    assert path.parent.parent.name == "artifacts"
    repo_root = Path(__file__).resolve().parents[2]
    assert path.resolve() == (repo_root / "artifacts" / "cache" / "hypothesis").resolve()
    assert path.resolve() != (repo_root / ".hypothesis").resolve()
