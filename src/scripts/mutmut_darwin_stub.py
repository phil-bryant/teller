#R001: Support Darwin-safe mutmut orchestration by providing a stable import path.
#R005: Keep stub behavior deterministic for subprocess-based mutation runs.
#R010: Stub setproctitle before mutmut import side effects on Darwin.
"""Stub setproctitle before mutmut imports it (macOS fork crash, mutmut #446)."""
import sys


class _SetproctitleStub:
    def setproctitle(self, *_args, **_kwargs):
        pass


sys.modules["setproctitle"] = _SetproctitleStub()
