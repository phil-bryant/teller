#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "00_verify_requirements_traceability.sh"
}

teardown() {
  teardown_shell_test
}

@test "prints usage with --help" {
  run bash "${FIXTURE_ROOT}/00_verify_requirements_traceability.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "passes in zero-arg mode when requirement and source IDs match" {
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

  run bash -c "cd '${FIXTURE_ROOT}' && ./00_verify_requirements_traceability.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All traceability checks passed."* ]]
}

@test "fails when requirement IDs are missing from source tags" {
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

  run bash "${FIXTURE_ROOT}/00_verify_requirements_traceability.sh" "${FIXTURE_ROOT}/req.md" "${FIXTURE_ROOT}/src.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing #R tags"* ]]
  [[ "$output" == *"R002"* ]]
}

@test "fails clearly when mapped source file is missing" {
  mkdir -p "${FIXTURE_ROOT}/requirements"
  cat > "${FIXTURE_ROOT}/requirements/sample-requirements.md" <<'EOF'
## Scope
Applies to `missing_source.sh`.

R001 Statement: One.
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./00_verify_requirements_traceability.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"references missing source file missing_source.sh"* ]]
}
