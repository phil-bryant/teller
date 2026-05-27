# Transaction Classifier UI Testing Support Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/UITestingSupport.swift`.

R001  Statement: Launch-mode detection must consistently classify the current process as normal mode or UI-testing mode.
Design: `detectAppLaunchMode(...)` returns `.uiTesting` when `--ui-testing` is present or `TELLER_UI_TEST_MODE=1`; otherwise it returns `.normal`.
Tests:
- R001-T01: Compute expected launch mode from the current process args/env and verify `detectAppLaunchMode(...)` matches it.

R005  Statement: UI-testing launch mode must route default view-model construction to fixture-backed APIs.
Design: `buildDefaultViewModel(...)` and `buildDefaultConnectViewModel(...)` switch on `detectAppLaunchMode(...)` and instantiate fixture APIs only for `.uiTesting`.
Tests:
- R005-T01: Enable `TELLER_UI_TEST_MODE=1`, build default classification/connect view models, run their initial load, and verify fixture-backed state is returned.

## Changelog

- 2026-05-26: Added requirements for launch-mode detection and default view-model fixture routing.
