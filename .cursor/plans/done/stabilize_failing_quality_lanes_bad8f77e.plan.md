---
name: Stabilize failing quality lanes
overview: Fix all currently failing test lanes by aligning traceability tags/tests, updating pinned dependencies, tightening the OpenAPI/Schemathesis contract for message search validation, and adjusting macOS UI regression timeout budgeting to reflect current suite scope.
todos:
  - id: fix-traceability
    content: "Patch missing #R source tags and missing/misplaced numbered test tags for R066/R064-T02/R105-R116/R071-T07/R010-T02/R073/R073-T02."
    status: completed
  - id: upgrade-direct-deps
    content: Bump pinned requirements for idna and starlette, then verify dependency freshness lane passes.
    status: completed
  - id: align-schemathesis-contract
    content: Tighten Schemathesis fixture and tests so empty-effective search criteria are modeled as 422 behavior, not success-path inputs.
    status: completed
  - id: rebudget-ui-timeout
    content: Raise macOS UI regression XCUITest timeout (and optionally prewarm) to prevent false lane timeouts after successful smoke execution.
    status: completed
  - id: rerun-gates
    content: Run targeted failing lanes then full parallel suite to confirm end-to-end green.
    status: completed
isProject: false
---

# Stabilize Failing Lanes Plan

## Goals
- Return `10_run_all_tests_parallel.sh` to green without weakening quality/security gates.
- Preserve strict behavior for dependency freshness and Schemathesis contract checking.
- Keep traceability docs/tests/source tags in 1:1 alignment.

## Workstreams

### 1) Fix requirements traceability failures (`t04`)
- Add missing source requirement tags where implementations already exist:
  - [src/macos-ui/Sources/TransactionClassifier/APIClient.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/APIClient.swift) for `R066` on transaction override path.
  - [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift)
  - [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+TransactionLoading.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+TransactionLoading.swift)
  - [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+ClassificationActions.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+ClassificationActions.swift)
  - [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+CategoryEditor.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+CategoryEditor.swift)
  - [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift)
  - [src/teller/teller_classification_api.py](/Users/phil/local/src/teller/src/teller/teller_classification_api.py) for `R073`.
- Add missing numbered test tags:
  - `R064-T02` in [src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift) (whitespace normalization scenario).
  - `R071-T07` in [src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift) (search-hit persistence across transaction selection).
  - `R010-T02` in a traceability-discovered fixture test file (preferred: new [src/macos-ui/Tests/TransactionClassifierTests/UITestingFixtureClassificationAPITests.swift](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/UITestingFixtureClassificationAPITests.swift), alternative: add inside [src/macos-ui/UITests/TransactionClassifierUITests.swift](/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift)).
- Fix numbered tag placement for `R073-T02` in [tests/py/test_teller_classification_api.py](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py) by moving it to an executable line or test signature so the parser counts it as in-block.

### 2) Fix dependency freshness gate (`t02`)
- Update pinned requirements in [requirements.txt](/Users/phil/local/src/teller/requirements.txt):
  - `idna==3.16 -> 3.17`
  - `starlette==1.1.0 -> 1.2.0`
- Re-run dependency freshness lane to confirm no blocking direct outdated pins remain.

### 3) Fix Schemathesis contract mismatch (`t12`)
- Keep API behavior strict (422 when no effective structured criteria), and align contract tooling to that behavior.
- Tighten generated Schemathesis OpenAPI fixture in [tests/py/security/schemathesis_fixture_prep.py](/Users/phil/local/src/teller/tests/py/security/schemathesis_fixture_prep.py) for `/v1/matchy/messages/search` so empty/no-op criteria are not treated as valid success-path inputs.
- Add/adjust API tests in [tests/py/test_teller_classification_api.py](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py) to lock expected 422 behavior for empty-effective criteria (e.g., `start_date=` / `end_date=null` with no real filter).
- If needed, clarify contract language in [requirements/teller/teller_classification_api-requirements.md](/Users/phil/local/src/teller/requirements/teller/teller_classification_api-requirements.md) to match strict validation semantics.

### 4) Fix macOS UI regression lane timeout (`t14`)
- Increase default XCUITest timeout budget in [tests/t14_run_macos_ui_regression_tests.sh](/Users/phil/local/src/teller/tests/t14_run_macos_ui_regression_tests.sh) to reflect current suite size and build+run wall time (current default 180s is too tight for ~133s execution plus xcodebuild overhead).
- Optionally add/prefer a prewarm build step (as used in crash lane) so test timeout measures runtime more than cold compilation.
- Keep scenario-selection defaults consistent between shell wrapper and UI test file (check [src/macos-ui/UITests/TransactionClassifierUITests.swift](/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift)).

## Validation Sequence
- Run focused lanes first: `t04`, `t02`, `t12`, `t14`.
- Then run `./10_run_all_tests_parallel.sh` and confirm all 18/18 pass.
- Verify no new regressions in Swift unit tests and API smoke tests.
