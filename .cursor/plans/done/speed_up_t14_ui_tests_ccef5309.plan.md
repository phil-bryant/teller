---
name: speed up t14 ui tests
overview: Make the t14 macOS UI regression suite run every scenario by default and remove the real slowdowns (dropped scenarios, serial tab-switch timeouts, post-success grace delay, per-search debounce), then close the guardrail gap that let agents sneak delays into the Swift test file.
todos:
  - id: default-all
    content: Set runner XCUITEST_SMOKE_DEFAULT_STEPS to 1-32 and fix Swift smokeDefaultSteps to full 1...scenarioCount so no scenario is skipped by default
    status: completed
  - id: select-tab
    content: Rewrite selectTab to poll all candidate locators in one loop instead of serial 1s-per-locator waits
    status: completed
  - id: grace
    content: Lower XCUITEST_SUCCESS_GRACE_SECONDS default to 1s in the runner
    status: completed
  - id: debounce
    content: Make mailcart search debounce env-tunable and near-zero under TELLER_UI_TEST_MODE, keeping 250ms in production
    status: completed
  - id: guard
    content: Extend R085-T01 bats test to scan the Swift UITest file (copy it into the fixture) for fixed sleep/Task.sleep/asyncAfter padding
    status: completed
  - id: reqs-bats
    content: Update requirements R075/R085 + changelog and the bats default-run assertion to expect 1-32
    status: completed
  - id: instrumentation
    content: Add per-scenario timing instrumentation in the smoke suite (timestamped lines + sorted summary + total) so before/after is measured, not estimated
    status: completed
isProject: false
---

## Context

t14 is the macOS UI regression gate: a runner [tests/t14_run_macos_ui_regression_tests.sh](tests/t14_run_macos_ui_regression_tests.sh) that drives a single XCUITest suite, `testMacOSUISmokeSuite`, in [src/macos-ui/UITests/TransactionClassifierUITests.swift](src/macos-ui/UITests/TransactionClassifierUITests.swift). There are 32 numbered scenarios.

The `waitUntil`/`waitForElement` helpers are already condition-driven (they return the instant the condition is true), so the large `waitTimeout * N` numbers are watchdog ceilings, not delays. Those stay. The genuine slowdowns are below.

## Slowdowns found

1. Scenarios silently dropped from the default run (the "don't run some tests" misinterpretation):
   - Runner default `XCUITEST_SMOKE_DEFAULT_STEPS="${...:-1-17,19-32}"` omits scenario 18 (`longListManualSelectionDoesNotRecenter`). See [tests/t14_run_macos_ui_regression_tests.sh](tests/t14_run_macos_ui_regression_tests.sh) line 77.
   - The Swift in-process fallback is even narrower: `smokeDefaultSteps` = `1...17` + `19...29`, dropping 18 and 30-32. See [src/macos-ui/UITests/TransactionClassifierUITests.swift](src/macos-ui/UITests/TransactionClassifierUITests.swift) lines 1101-1105.

2. Serial per-candidate timeout in `selectTab` (real wall-clock waste): it tries 5 locator types and calls `waitForElement(candidate, timeout: 1)` on each in sequence, so any tab whose real control is not the first locator burns up to ~1-4s of dead time per switch. With many `ensure*Tab` calls across 32 scenarios this compounds. See lines 818-834.

3. Fixed post-success grace delay: `XCUITEST_SUCCESS_GRACE_SECONDS` defaults to 5, so after `** TEST SUCCEEDED **` the runner sleeps ~5s before stopping xcodebuild on every successful run. See line 31 and the Python watchdog at lines 152-163.

4. App-side per-search debounce hits the UI tests: `mailcartSearchDebounceNanoseconds = 250_000_000` runs a `Task.sleep` on every email search ([ClassificationViewModel.swift](src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift) line 141, used in [ClassificationViewModel+MatchReview.swift](src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift) line 58). Scenarios 14/15/16/30/32 do many searches; scenario 32 alone does ~8 (~2s of pure debounce).

5. Guardrail gap (the root cause of "agents sneaking delays"): requirement R085 says both the runner and the Swift file must be free of fixed delays, but the bats test only greps the runner. See [tests/sh/t14_run_macos_ui_regression_tests.bats](tests/sh/t14_run_macos_ui_regression_tests.bats) lines 324-328. The Swift file is unguarded, so sleeps can be reintroduced undetected.

## Changes

### Run everything by default
- In [tests/t14_run_macos_ui_regression_tests.sh](tests/t14_run_macos_ui_regression_tests.sh): set `XCUITEST_SMOKE_DEFAULT_STEPS` default to `1-32` (include scenario 18). `extended/full` already maps to `1-32`, so all profiles now run the full set.
- In [src/macos-ui/UITests/TransactionClassifierUITests.swift](src/macos-ui/UITests/TransactionClassifierUITests.swift): change `smokeDefaultSteps` to the full `Set(1...scenarioCount)` so the in-process fallback never drops scenarios.

### Remove the serial tab-switch timeout
- Rewrite `selectTab` to poll all candidate locators inside one `waitUntil` loop and click the first that exists, instead of waiting a full second on each locator in series. Returns the instant any tab control appears.

### Trim the post-success grace delay
- Lower the runner default `XCUITEST_SUCCESS_GRACE_SECONDS` to `1` (keep it overridable). The grace exists only to reap a post-success linger; 1s is enough to detect a hang while shaving ~4s off every green run.

### Shorten the debounce under UI-test mode only
- Make the debounce env-tunable: read an override (e.g. `TELLER_UI_TEST_MODE=1` -> a near-zero debounce, or a `TELLER_MAILCART_DEBOUNCE_MS` env) in [ClassificationViewModel.swift](src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift), defaulting to the production 250ms. The UI host already sets `TELLER_UI_TEST_MODE=1`, so search-heavy scenarios stop paying 250ms per query while production behavior is unchanged.

### Close the guardrail gap (prevent re-introduction)
- Extend the R085-T01 bats test in [tests/sh/t14_run_macos_ui_regression_tests.bats](tests/sh/t14_run_macos_ui_regression_tests.bats) to also fail on fixed delays in the copied Swift UITest file: grep for `sleep `, `usleep`, `Thread.sleep`, `Task.sleep`, and `DispatchQueue.*asyncAfter` used as interaction padding. Make sure the bats `setup` copies the Swift file into the fixture so the test can scan it.
- Update [requirements/t14_run_macos_ui_regression_tests-requirements.md](requirements/t14_run_macos_ui_regression_tests-requirements.md): R075 default becomes `1-32`, and R085 design notes the Swift file is now actually enforced. Add a changelog entry.

### Update the existing bats expectations
- The "defaults run snapshot and xcodebuild" test asserts `1-17,19-32` (line 194) and "extended profile" asserts `1-32` (line 217). Update the default-run assertion to `1-32`.

### Add per-scenario timing instrumentation (measure, don't estimate)
Goal: get a real per-run breakdown so we know where the ~150s actually goes and can prove the before/after delta instead of guessing.

In [src/macos-ui/UITests/TransactionClassifierUITests.swift](src/macos-ui/UITests/TransactionClassifierUITests.swift):
- Wrap each scenario dispatch in `testMacOSUISmokeSuite` (the `switch step` loop, lines 55-115) with a timing helper instead of calling the `run*Scenario()` functions directly. Sketch:

```swift
private func timed(_ step: Int, _ name: String, _ body: () -> Void) {
    let start = DispatchTime.now()
    body()
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    Self.scenarioTimingsMs.append((step, name, ms))
    print(String(format: "⏱ t14 scenario %02d %@: %.0f ms", step, name, ms))
}
```

- Reuse the existing `XCUITEST_SCENARIOS` name list (already in the runner) by mirroring the names in the suite, or derive the label from the step number, so each line is greppable: `⏱ t14 scenario 32 advancedEmailSearch: 2840 ms`.
- Also time the one-time app launch in `setUp` and the per-test fixture-ready wait in `setUpWithError` so launch/build-adjacent cost is visible separately from scenario cost.
- In `tearDown`, print a summary sorted slowest-first plus the total, e.g.:

```
⏱ t14 timing summary (slowest first)
   32 advancedEmailSearch       2840 ms
   17 nextUnclassifiedScrolls... 1910 ms
   ...
⏱ t14 scenarios total: 41320 ms over 32 scenarios; app launch: 5120 ms
```

- Keep it always-on but cheap (just `DispatchTime` + `print`); the lines flow through `xcodebuild` stdout and the runner's heartbeat pass-through, so they show up in normal gate output and in the `.xcresult`.
- Gate behind an env flag only if the noise is unwanted: respect `TELLER_UI_TEST_TIMING` (default on) so it can be silenced without code changes. Minor decision; defaulting on since the whole point is visibility.

This adds negligible wall-clock (microseconds per scenario) and gives a concrete per-scenario table to validate the debounce/grace/tab-switch wins and to spot the next bottleneck (likely launch + snapshot lane).

## Out of scope / deliberately unchanged
- The `waitTimeout`/`launchTimeout` ceilings and `* N` multipliers stay: they are early-exit watchdogs, not pacing delays. If a tightened path genuinely breaks, that is a real regression to fix (per your guidance), not a reason to pad timeouts.

## Verification
- `bats tests/sh/t14_run_macos_ui_regression_tests.bats` (stubbed; validates defaults now emit `1-32`, both profiles run all scenarios, and the Swift file is scanned for delays).
- Run the real gate once: `./tests/t14_run_macos_ui_regression_tests.sh` and confirm all 32 scenarios execute and the run ends promptly after `** TEST SUCCEEDED **`.
- Use the new `⏱ t14 timing summary` block to capture a before/after: record the current per-scenario table first (baseline), then re-run after the changes and diff the total to get the real speedup instead of the estimate.