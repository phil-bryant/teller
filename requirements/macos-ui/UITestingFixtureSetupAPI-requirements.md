# Transaction Classifier UI Testing Setup Fixture Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/UITestingFixtureSetupAPI.swift`.

R020  Statement: Setup fixture API must provide deterministic readiness and smoke-check outputs.
Design: `UITestingFixtureSetupAPI` returns fixed setup paths/readiness and a passing smoke-check payload for UI automation flows.
Tests:
- R020-T01: Load setup snapshot and smoke-check result and verify expected fixture values.

## Changelog

- 2026-05-26: Added requirements for split setup fixture API.
