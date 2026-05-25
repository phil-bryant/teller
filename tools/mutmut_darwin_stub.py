"""Stub setproctitle before mutmut imports it (macOS fork crash, mutmut #446)."""
import sys


class _SetproctitleStub:
    def setproctitle(self, *_args, **_kwargs):
        pass


sys.modules["setproctitle"] = _SetproctitleStub()
