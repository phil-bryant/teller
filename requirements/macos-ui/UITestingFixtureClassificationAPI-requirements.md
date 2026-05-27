# Transaction Classifier UI Testing Classification Fixture Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/UITestingFixtureClassificationAPI.swift`.

R010  Statement: Classification fixture API must provide deterministic category/transaction/message behavior for smoke and regression UI tests.
Design: `UITestingFixtureAPI` seeds stable categories/transactions, supports pagination/search/match actions, and returns deterministic message/search fixtures.
Tests:
- R010-T01: Fetch fixture categories and transactions and verify stable seeded identifiers/count semantics.

## Changelog

- 2026-05-26: Added requirements for split classification fixture API.
