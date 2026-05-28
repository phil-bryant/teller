# Transaction Classifier UI Testing Classification Fixture Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/UITestingFixtureClassificationAPI.swift`.

R010  Statement: Classification fixture API must provide deterministic category/transaction/message behavior for smoke and regression UI tests.
Design: `UITestingFixtureAPI` seeds stable categories/transactions, supports pagination/search/match actions, and returns deterministic message/search fixtures. `fetchCandidates` mirrors backend R060 by always surfacing the transaction's active matched `email_message_id` as a candidate row (deduped against any seeded run candidate), so an overridden/linked email stays visible. `fetchMessage` returns deterministic bodies for seeded ids and synthesizes a generic message for any other id (including dynamically overridden emails) so the linked email always renders a body.
Tests:
- R010-T01: Fetch fixture categories and transactions and verify stable seeded identifiers/count semantics.
- R010-T02: With the match fixture enabled, fetch candidates for a transaction whose active matched email is not a seeded run candidate and verify the active email is returned as a candidate with a loadable message body; after overriding an unmatched transaction with a searched email, verify that email becomes its candidate.

## Changelog

- 2026-05-26: Added requirements for split classification fixture API.
- 2026-05-28: Extended R010 so `fetchCandidates` unions the active matched email (backend R060 parity) and `fetchMessage` synthesizes bodies for non-seeded ids; added R010-T02.
