---
name: fix-t14-match-classify-return
overview: Restore the t14 default smoke run so it returns to Match & Classify after the Connect/Manage Categories tabs (scenarios 30-32), and harden the post-success grace-kill so it only triggers on the authoritative end marker and is no longer silent.
todos:
  - id: default-steps
    content: Change XCUITEST_SMOKE_DEFAULT_STEPS from 1-17,19-29 to 1-17,19-32 in tests/t14_run_macos_ui_regression_tests.sh
    status: completed
  - id: harden-grace
    content: Restore TIMEOUT_HEARTBEAT_SECONDS default to 15 and narrow the grace-kill success trigger to only '** TEST SUCCEEDED **' in the Python run_with_timeout helper
    status: completed
  - id: update-bats
    content: Update bats default-steps assertion to 1-17,19-32; keep R020-T03 and R075-T02
    status: completed
  - id: update-requirements
    content: Rework R075 (default returns to Match & Classify 30-32), adjust R020 wording, add changelog entry
    status: completed
isProject: false
---

# Fix t14: restore Match & Classify return pass + de-spook the grace-kill

## Root cause
Two prior changes combined to produce the symptom (default run ends after the two tabs, "window closes", sits, reports success, skips the final Match & Classify scenarios):

1. Real bug (committed `214c0533`, May 26): the default smoke step list was narrowed to `1-17,19-29`, which drops scenarios 30 (`matchStatePickerAllValues`), 31 (`advancedTransactionFilter`), 32 (`advancedEmailSearch`) — the scenarios that return to Match & Classify after Connect (20-25) and Manage Categories (26-29). Before that commit, a no-arg run left `XCUITEST_STEPS` unset and the Swift suite ran all 1-32.
2. Cosmetic/confusing (uncommitted working tree): a "post-success linger" grace-kill was added to `run_with_timeout`, plus `TIMEOUT_HEARTBEAT_SECONDS` was flipped from 15 to 0 (silent). After the suite legitimately finishes at step 29, this kills the lingering `xcodebuild` and exits 0 — which looks like "closed the window and is just sitting there."

The grace-kill itself is a legitimate guard against the known macOS issue where `xcodebuild` prints `** TEST SUCCEEDED **` then hangs (otherwise the runner would hit the 180s timeout and report a false failure). So I will harden it, not remove it.

## Changes

### 1. Restore the return-to-Match & Classify scenarios in the default run
[tests/t14_run_macos_ui_regression_tests.sh](tests/t14_run_macos_ui_regression_tests.sh)
- Change the smoke default from `1-17,19-29` to `1-17,19-32` (keeps 18 excluded as before, but brings back 30-32):

```bash
XCUITEST_SMOKE_DEFAULT_STEPS="${XCUITEST_SMOKE_DEFAULT_STEPS:-1-17,19-32}"
```

### 2. Harden + de-spook the grace-kill
[tests/t14_run_macos_ui_regression_tests.sh](tests/t14_run_macos_ui_regression_tests.sh)
- Restore heartbeat so the run is not silent: `TIMEOUT_HEARTBEAT_SECONDS="${TIMEOUT_HEARTBEAT_SECONDS:-15}"`.
- In the embedded Python `run_with_timeout`, narrow the success trigger to ONLY the authoritative end-of-run marker `** TEST SUCCEEDED **`. Drop the looser heuristics (`Test Suite '...' passed at`, `testMacOSUISmokeSuite ... passed (`) so the grace timer can never start before xcodebuild's final success line.
- Keep the live output streaming (it's an improvement) and keep the SIGTERM-after-grace behavior on that single marker.

### 3. Update tests to match
[tests/sh/t14_run_macos_ui_regression_tests.bats](tests/sh/t14_run_macos_ui_regression_tests.bats)
- `defaults run snapshot and xcodebuild...` (line ~194): assert the default output contains `1-17,19-32` (was `1-17,19-29`).
- Keep `XCUITest runner exits promptly after post-success linger` (R020-T03) — it prints `** TEST SUCCEEDED **` then hangs, which still triggers the hardened path.
- `extended profile includes advanced filter scenarios` (R075-T02) stays asserting `1-32`.

### 4. Update requirements/traceability
[requirements/t14_run_macos_ui_regression_tests-requirements.md](requirements/t14_run_macos_ui_regression_tests-requirements.md)
- Rework R075 so the default smoke profile is required to complete the Match & Classify return pass (scenarios 30-32) after the Connect/Manage Categories tabs; update R075-T01 to assert the default `XCUITEST_STEPS` includes 30-32, keep R075-T02 for extended.
- Tweak R020 design wording: grace-kill triggers only on the final `** TEST SUCCEEDED **` and keeps heartbeat progress visible.
- Add a Changelog entry dated today noting the default now returns to Match & Classify and the grace-kill was hardened.

## Validation
- `bats tests/sh/t14_run_macos_ui_regression_tests.bats` (stubs `xcodebuild`, no Xcode needed) — confirms default steps string, grace-kill behavior, extended profile.
- A real `./tests/t14_run_macos_ui_regression_tests.sh` run should now visibly go Match & Classify -> Connect -> Manage Categories -> back to Match & Classify (30-32), then finish.

## Notes / watch items
- Including scenario 30 (the "heavy all-values match-state sweep") in the default again makes the run longer. If a real run approaches the 180s `XCUITEST_TIMEOUT_SECONDS`, we should bump that env default — flagging rather than changing it blindly.
- I'm intentionally keeping scenario 18 (`longListManualSelectionDoesNotRecenter`) excluded from smoke, matching prior behavior; your complaint was specifically about the post-tabs Match & Classify scenarios (30-32). Say the word if you want 18 back in too.