# macOS UI SwiftPM Lock Helper Requirements

## Scope

Applies to `src/scripts/macos_ui_swift_lock.sh`.

R001  Statement: Serialize SwiftPM operations with an exclusive lock directory protocol.
Design: Acquire lock via `mkdir <lock>.d`, write owner PID marker, run wrapped command under trap-based lock cleanup, and return wrapped command exit status.
Tests:
- R001-T01: Verify successful lock acquisition runs command and removes lock artifacts on exit.

R005  Statement: Detect and clean stale lock owners before waiting.
Design: Remove stale lock directories when PID markers are missing or point to dead processes, then retry acquisition.
Tests:
- R005-T01: Verify stale lock cleanup paths recover and allow command execution.

R010  Statement: Enforce bounded wait with periodic operator diagnostics.
Design: Validate timeout/log interval inputs, emit periodic wait logs, and fail with explicit timeout details when lock acquisition exceeds configured budget.
Tests:
- R010-T01: Verify lock contention emits wait diagnostics and times out with non-zero exit when budget is exceeded.
