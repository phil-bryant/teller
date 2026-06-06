"""Stub setproctitle before mutmut imports it (macOS fork crash, mutmut #446)."""
import sys


class _SetproctitleStub:
    def setproctitle(self, *_args, **_kwargs):
        #R384: Provide no-op setproctitle fallback for Darwin mutmut.
        pass


sys.modules["setproctitle"] = _SetproctitleStub()
