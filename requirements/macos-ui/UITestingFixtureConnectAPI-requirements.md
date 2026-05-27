# Transaction Classifier UI Testing Connect Fixture Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/UITestingFixtureConnectAPI.swift`.

R015  Statement: Connect fixture API must support deterministic add/edit/delete context flows.
Design: `UITestingFixtureConnectAPI` starts with seeded contexts and mutates in-memory contexts for reconnect/add/delete/session actions.
Tests:
- R015-T01: Add a fixture context and verify it appears with expected suffix-key behavior and updated context count.

## Changelog

- 2026-05-26: Added requirements for split connect fixture API.
