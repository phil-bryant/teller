#!/usr/bin/env bats


load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "t04_run_requirements_traceability_tests.sh"
  mv "${FIXTURE_ROOT}/t04_run_requirements_traceability_tests.sh" "${FIXTURE_ROOT}/verify_requirements_traceability.sh"
}

teardown() {
  teardown_shell_test
}

make_numbered_traceability_mismatch_fixture() {
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/fixture-requirements.md" <<'EOF'
# Numbered Traceability Fixture Requirements

## Scope

Applies to `fixture.sh`.

R777  Statement: Numbered traceability fixture behavior.
Tests:
- R777-T01: Numbered traceability fixture baseline.
- R777-T04: Numbered traceability fixture intentionally skips T03.
EOF
  cat > "${FIXTURE_ROOT}/fixture.sh" <<'EOF'
#!/bin/bash
# #R777: Numbered traceability fixture implementation.
echo "fixture"
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/fixture.bats" <<'EOF'
#!/usr/bin/env bats

@test "fixture numbered traceability tags" {
  #R777-T01: Numbered traceability fixture baseline.
  #R777-T03: Numbered traceability fixture extra tag not declared in requirements.
  #R777: Numbered traceability fixture coverage.
  [ 1 -eq 1 ]
}
EOF
  chmod +x "${FIXTURE_ROOT}/fixture.sh"
}

@test "prints usage with --help" {
  #R001-T01
  run bash "${FIXTURE_ROOT}/verify_requirements_traceability.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "passes in zero-arg mode when requirement and source IDs match" {
  #R005-T01 #R010-T01 #R035-T01 #R045-T02
  mkdir -p "${FIXTURE_ROOT}/requirements"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
Tests:
- R001-T01: Sample tagged test coverage.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
#R001: One.
EOF
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  #R001-T01: Sample tagged test coverage.
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All traceability checks passed."* ]]
}

@test "fails when requirement IDs are missing from source tags" {
  #R020-T01 #R025-T01 #R030-T01 #R030-T02 #R035-T02
  cat > "${FIXTURE_ROOT}/req.md" <<'EOF'
## Scope
Applies to `src.sh`.

R001 Statement: One.
R002 Statement: Two.
EOF
  cat > "${FIXTURE_ROOT}/src.sh" <<'EOF'
#!/usr/bin/env bash
#R001: One.
EOF

  run bash "${FIXTURE_ROOT}/verify_requirements_traceability.sh" "${FIXTURE_ROOT}/req.md" "${FIXTURE_ROOT}/src.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing #R tags"* ]]
  [[ "$output" == *"R002"* ]]
}

@test "fails clearly when mapped source file is missing" {
  #R015-T01 #R015-T02
  mkdir -p "${FIXTURE_ROOT}/requirements"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `missing_source.sh`.

R001 Statement: One.
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"references missing source file missing_source.sh"* ]]
}

@test "fails when requirement lacks any tagged test coverage" {
  #R050-T01 #R065-T01 #R065-T03
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
#R001: One.
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL (test-traceability)"* ]]
  [[ "$output" == *"R001"* ]]
}

@test "requires UI test lane for UI-testing requirements" {
  #R050-T02 #R055-T01 #R060-T01
  mkdir -p "${FIXTURE_ROOT}/requirements/macos-ui"
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/Sources/TransactionClassifier"
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/Tests/TransactionClassifierTests"
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/UITests"
  cat > "${FIXTURE_ROOT}/requirements/macos-ui/Feature-requirements.md" <<'EOF'
## Scope
Applies to `src/macos-ui/Sources/TransactionClassifier/Feature.swift`.

R001 Statement: Core behavior.
Tests:
- R001-T01: Model lane traceability.
R002 Statement: UI-testing mode must toggle interactions.
Tests:
- R002-T01: UI lane traceability.
EOF
  cat > "${FIXTURE_ROOT}/src/macos-ui/Sources/TransactionClassifier/Feature.swift" <<'EOF'
// #R001: Core behavior.
// #R002: UI-testing mode must toggle interactions.
EOF
  cat > "${FIXTURE_ROOT}/src/macos-ui/Tests/TransactionClassifierTests/FeatureTests.swift" <<'EOF'
import XCTest

final class FeatureTests: XCTestCase {
  func testModelLaneTraceability() {
    // #R001-T01: Model lane traceability.
    // #R001
    XCTAssertTrue(true)
  }
}
EOF
  cat > "${FIXTURE_ROOT}/src/macos-ui/UITests/FeatureUITests.swift" <<'EOF'
import XCTest

final class FeatureUITests: XCTestCase {
  func testUILaneTraceability() {
    // #R002-T01: UI lane traceability.
    // #R002
    XCTAssertTrue(true)
  }
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh requirements/macos-ui/Feature-requirements.md src/macos-ui/Sources/TransactionClassifier/Feature.swift"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (test-traceability)"* ]]
}

@test "fails UI-testing requirement when only model lane has tags" {
  #R065-T02
  mkdir -p "${FIXTURE_ROOT}/requirements/macos-ui"
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/Sources/TransactionClassifier"
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/Tests/TransactionClassifierTests"
  cat > "${FIXTURE_ROOT}/requirements/macos-ui/Feature-requirements.md" <<'EOF'
## Scope
Applies to `src/macos-ui/Sources/TransactionClassifier/Feature.swift`.

R001 Statement: UI testing must verify this behavior.
EOF
  cat > "${FIXTURE_ROOT}/src/macos-ui/Sources/TransactionClassifier/Feature.swift" <<'EOF'
// #R001: UI testing must verify this behavior.
EOF
  cat > "${FIXTURE_ROOT}/src/macos-ui/Tests/TransactionClassifierTests/FeatureTests.swift" <<'EOF'
// #R001
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh requirements/macos-ui/Feature-requirements.md src/macos-ui/Sources/TransactionClassifier/Feature.swift"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL (test-traceability)"* ]]
  [[ "$output" == *"R001"* ]]
}

@test "teller module requirements map only to matching python test file" {
  #R050-T03
  mkdir -p "${FIXTURE_ROOT}/requirements/teller" "${FIXTURE_ROOT}/src/teller" "${FIXTURE_ROOT}/tests/py"
  cat > "${FIXTURE_ROOT}/requirements/teller/teller_object-requirements.md" <<'EOF'
## Scope
Applies to `src/teller/teller_object.py`.

R001 Statement: One.
EOF
  cat > "${FIXTURE_ROOT}/src/teller/teller_object.py" <<'EOF'
#R001: One.
EOF
  cat > "${FIXTURE_ROOT}/tests/py/test_teller_object.py" <<'EOF'
# no matching tags here on purpose
EOF
  cat > "${FIXTURE_ROOT}/tests/py/test_teller_classification_api.py" <<'EOF'
#R001
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh requirements/teller/teller_object-requirements.md src/teller/teller_object.py"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- tests: ${FIXTURE_ROOT}/tests/py/test_teller_object.py"* ]]
  [[ "$output" != *"test_teller_classification_api.py"* ]]
  [[ "$output" == *"R001"* ]]
}

@test "fails when source uses bundled header #R tags" {
  #R070-T01
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
Tests:
- R001-T01: Scoped source test trace.
R005 Statement: Two.
Tests:
- R005-T01: Scoped source test trace.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
# #R001 #R005 #R010
echo "fixture"
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  #R001
  #R005
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh requirements/sample-requirements.md sample_script.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL (anti-cheat)"* ]]
}

@test "fails when source tags are unscoped" {
  #R070-T02
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
Tests:
- R001-T01: Scoped source test trace.
R005 Statement: Two.
Tests:
- R005-T01: Scoped source test trace.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
# #R001
echo "first"
# #R005
echo "second"
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  #R001
  #R005
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh requirements/sample-requirements.md sample_script.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing scoped #R comments"* ]]
}

@test "passes when source tags are scoped with #Rxxx:" {
  #R070-T03
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
Tests:
- R001-T01: Scoped source test trace.
R005 Statement: Two.
Tests:
- R005-T01: Scoped source test trace.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
# #R001: One.
echo "first"
# #R005: Two.
echo "second"
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  #R001-T01: Scoped source test trace.
  #R005-T01: Scoped source test trace.
  #R001
  #R005
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh requirements/sample-requirements.md sample_script.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (test-traceability)"* ]]
}

@test "requirements-only mode skips source and test checks" {
  #R075-T01 #R075-T02
  mkdir -p "${FIXTURE_ROOT}/requirements"
  cat > "${FIXTURE_ROOT}/requirements/phase-requirements.md" <<'EOF'
# Phase Requirements

## Scope

Requirements-only mode: true.

R001 Statement: Placeholder requirement.
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (requirements-only)"* ]]
}

@test "fails full-run mode when repository software has no requirements coverage" {
  #R085-T01
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `covered.sh`.

R001 Statement: Covered shell source.
EOF
  cat > "${FIXTURE_ROOT}/covered.sh" <<'EOF'
#!/usr/bin/env bash
#R001: covered.
EOF
  chmod +x "${FIXTURE_ROOT}/covered.sh"
  cat > "${FIXTURE_ROOT}/orphan.sh" <<'EOF'
#!/usr/bin/env bash
echo "orphan"
EOF
  chmod +x "${FIXTURE_ROOT}/orphan.sh"
  cat > "${FIXTURE_ROOT}/tests/sh/sample.bats" <<'EOF'
@test "covered shell source" {
  #R001-T01: covered shell source.
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"repository software files missing requirements coverage"* ]]
  [[ "$output" == *"orphan.sh"* ]]
}

@test "fails full-run mode when src scripts have no requirements coverage" {
  #R085-T02
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh" "${FIXTURE_ROOT}/src/scripts"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `covered.sh`.

R001 Statement: Covered shell source.
EOF
  cat > "${FIXTURE_ROOT}/covered.sh" <<'EOF'
#!/usr/bin/env bash
#R001: covered.
EOF
  chmod +x "${FIXTURE_ROOT}/covered.sh"
  cat > "${FIXTURE_ROOT}/src/scripts/orphan.sh" <<'EOF'
#!/usr/bin/env bash
echo "orphan script"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/orphan.sh"
  cat > "${FIXTURE_ROOT}/tests/sh/sample.bats" <<'EOF'
@test "covered shell source" {
  #R001-T01: covered shell source.
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"repository software files missing requirements coverage"* ]]
  [[ "$output" == *"src/scripts/orphan.sh"* ]]
}

@test "fails numbered script test coverage when companion bats file is missing" {
  #R040-T01 #R045-T01 #R080-T01
  mkdir -p "${FIXTURE_ROOT}/requirements"
  cat > "${FIXTURE_ROOT}/01_alpha.sh" <<'EOF'
#!/usr/bin/env bash
#R001: alpha behavior.
EOF
  chmod +x "${FIXTURE_ROOT}/01_alpha.sh"
  cat > "${FIXTURE_ROOT}/requirements/01_alpha-requirements.md" <<'EOF'
## Scope
Applies to `01_alpha.sh`.

R001 Statement: alpha behavior.
Tests:
- R001-T01: alpha behavior traceability.
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"numbered scripts missing companion shell tests"* ]]
  [[ "$output" == *"01_alpha.sh"* ]]
}

@test "passes numbered script test coverage when bats companion exists" {
  #R040-T02 #R080-T02
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/01_alpha.sh" <<'EOF'
#!/usr/bin/env bash
#R001: alpha behavior.
EOF
  chmod +x "${FIXTURE_ROOT}/01_alpha.sh"
  cat > "${FIXTURE_ROOT}/requirements/01_alpha-requirements.md" <<'EOF'
## Scope
Applies to `01_alpha.sh`.

R001 Statement: alpha behavior.
Tests:
- R001-T01: alpha behavior traceability.
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/01_alpha.bats" <<'EOF'
@test "alpha behavior traceability" {
  #R001-T01: alpha behavior traceability.
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"numbered script test coverage complete"* ]]
}

@test "fails when numbered test tags are missing" {
  #R090-T01
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
Tests:
- R001-T01: Sample tagged test coverage.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
#R001: One.
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL (numbered-test-tags)"* ]]
  [[ "$output" == *"Missing in tests (present in requirements)"* ]]
  [[ "$output" == *"R001-T01"* ]]
}

@test "fails when numbered tags are in test-file header comments" {
  #R090-T07
  #R090
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
Tests:
- R001-T01: Sample tagged test coverage.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
#R001: One.
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
# #R001-T01: misplaced header tag.
@test "sample requirement traceability" {
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL (numbered-test-tag-placement)"* ]]
  [[ "$output" == *"#R001-T01"* ]]
}

@test "passes when numbered tags are inside executable test blocks" {
  #R090-T08
  #R090
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
Tests:
- R001-T01: Sample tagged test coverage.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
#R001: One.
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  #R001-T01: Sample tagged test coverage.
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (numbered-test-tags)"* ]]
}

@test "fails numbered test tracing when requirements and tests are not 1:1 in both directions" {
  #R090-T02 #R090-T03
  #R090
  make_numbered_traceability_mismatch_fixture

  run bash "${FIXTURE_ROOT}/verify_requirements_traceability.sh" "${FIXTURE_ROOT}/requirements/fixture-requirements.md" "${FIXTURE_ROOT}/fixture.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing in tests (present in requirements)"* ]]
  [[ "$output" == *"R777-T04"* ]]
  [[ "$output" == *"Missing in requirements (present in tests)"* ]]
  [[ "$output" == *"R777-T03"* ]]
}

@test "fails numbered test tracing when Tests bullets are malformed" {
  #R090-T04
  #R090
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/fixture-requirements.md" <<'EOF'
# Fixture Requirements

## Scope

Applies to `fixture.sh`.

R001  Statement: First behavior.
Tests:
- Verify first behavior without numbered test ID.
EOF
  cat > "${FIXTURE_ROOT}/fixture.sh" <<'EOF'
#!/bin/bash
# #R001: First behavior.
echo "fixture"
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/fixture.bats" <<'EOF'
@test "fixture requirement tags" {
  #R001-T01: First behavior test trace.
  #R001: First behavior test trace.
  [ 1 -eq 1 ]
}
EOF

  run bash "${FIXTURE_ROOT}/verify_requirements_traceability.sh" "${FIXTURE_ROOT}/requirements/fixture-requirements.md" "${FIXTURE_ROOT}/fixture.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unnumbered/invalid test bullet"* ]]
  [[ "$output" == *"FAIL (requirements-numbered-tests)"* ]]
}

@test "requirements-only mode skips numbered test 1:1 checks" {
  #R090-T05
  #R070
  #R090
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/phase-requirements.md" <<'EOF'
# Phase Requirements

## Scope

Requirements-only mode: true.

R777  Statement: Placeholder requirement while implementation is pending.
Tests:
- R777-T01: Placeholder numbered test entry while implementation is pending.
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/phase.bats" <<'EOF'
@test "placeholder" {
  #R777-T99: Intentionally mismatched but should be skipped for requirements-only docs.
  [ 1 -eq 1 ]
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (requirements-only)"* ]]
}

@test "fails when requirement ID lacks numbered Rxxx-T## entries" {
  #R090-T06
  #R090
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
Tests:
- Verify behavior without numbered id.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
#R001: One.
EOF
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  #R001-T01: existing numbered test tag.
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing Rxxx-T## entries"* ]]
  [[ "$output" == *"R001"* ]]
}
