#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "00_verify_requirements_traceability.sh"
  mv "${FIXTURE_ROOT}/00_verify_requirements_traceability.sh" "${FIXTURE_ROOT}/verify_requirements_traceability.sh"
}

teardown() {
  teardown_shell_test
}

@test "prints usage with --help" {
  #R001
  run bash "${FIXTURE_ROOT}/verify_requirements_traceability.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "passes in zero-arg mode when requirement and source IDs match" {
  #R005 #R010 #R035 #R040 #R045
  mkdir -p "${FIXTURE_ROOT}/requirements"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
#R001
EOF
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/tests/sh/sample_script.bats" <<'EOF'
@test "sample requirement traceability" {
  #R001
  true
}
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All traceability checks passed."* ]]
}

@test "fails when requirement IDs are missing from source tags" {
  #R020 #R025 #R030
  cat > "${FIXTURE_ROOT}/req.md" <<'EOF'
## Scope
Applies to `src.sh`.

R001 Statement: One.
R002 Statement: Two.
EOF
  cat > "${FIXTURE_ROOT}/src.sh" <<'EOF'
#!/usr/bin/env bash
#R001
EOF

  run bash "${FIXTURE_ROOT}/verify_requirements_traceability.sh" "${FIXTURE_ROOT}/req.md" "${FIXTURE_ROOT}/src.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing #R tags"* ]]
  [[ "$output" == *"R002"* ]]
}

@test "fails clearly when mapped source file is missing" {
  #R015
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
  #R050 #R065
  mkdir -p "${FIXTURE_ROOT}/requirements" "${FIXTURE_ROOT}/tests/sh"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `sample_script.sh`.

R001 Statement: One.
EOF
  cat > "${FIXTURE_ROOT}/sample_script.sh" <<'EOF'
#!/usr/bin/env bash
#R001
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
  #R055 #R060
  mkdir -p "${FIXTURE_ROOT}/requirements/macos-ui"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests/TransactionClassifierTests"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/UITests"
  cat > "${FIXTURE_ROOT}/requirements/macos-ui/Feature-requirements.md" <<'EOF'
## Scope
Applies to `macos-ui/Sources/TransactionClassifier/Feature.swift`.

R001 Statement: Core behavior.
R002 Statement: UI-testing mode must toggle interactions.
EOF
  cat > "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier/Feature.swift" <<'EOF'
// #R001
// #R002
EOF
  cat > "${FIXTURE_ROOT}/macos-ui/Tests/TransactionClassifierTests/FeatureTests.swift" <<'EOF'
// #R001
EOF
  cat > "${FIXTURE_ROOT}/macos-ui/UITests/FeatureUITests.swift" <<'EOF'
// #R002
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh requirements/macos-ui/Feature-requirements.md macos-ui/Sources/TransactionClassifier/Feature.swift"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (test-traceability)"* ]]
}

@test "fails UI-testing requirement when only model lane has tags" {
  mkdir -p "${FIXTURE_ROOT}/requirements/macos-ui"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests/TransactionClassifierTests"
  cat > "${FIXTURE_ROOT}/requirements/macos-ui/Feature-requirements.md" <<'EOF'
## Scope
Applies to `macos-ui/Sources/TransactionClassifier/Feature.swift`.

R001 Statement: UI testing must verify this behavior.
EOF
  cat > "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier/Feature.swift" <<'EOF'
// #R001
EOF
  cat > "${FIXTURE_ROOT}/macos-ui/Tests/TransactionClassifierTests/FeatureTests.swift" <<'EOF'
// #R001
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./verify_requirements_traceability.sh requirements/macos-ui/Feature-requirements.md macos-ui/Sources/TransactionClassifier/Feature.swift"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL (test-traceability)"* ]]
  [[ "$output" == *"R001"* ]]
}
