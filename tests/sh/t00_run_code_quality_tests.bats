#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "t00_run_code_quality_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/teller" "${FIXTURE_ROOT}/src/scripts" "${FIXTURE_ROOT}/tests"
  echo "x = 1" > "${FIXTURE_ROOT}/src/teller/sample.py"
  # Keep Periphery in the fixture rooted at FIXTURE_ROOT so cd does not need a real Swift package.
  export PERIPHERY_PROJECT_DIR="."
}

teardown() {
  teardown_shell_test
}

stub_vulture_clean() {
  cat > "${STUB_BIN}/vulture" <<'EOF'
#!/usr/bin/env bash
echo "vulture $*" >> "${CALLS_LOG}"
echo "vulture-clean"
exit 0
EOF
  chmod +x "${STUB_BIN}/vulture"
}

stub_vulture_findings() {
  cat > "${STUB_BIN}/vulture" <<'EOF'
#!/usr/bin/env bash
echo "vulture $*" >> "${CALLS_LOG}"
echo "unused function 'demo'"
exit 1
EOF
  chmod +x "${STUB_BIN}/vulture"
}

stub_vulture_findings_exit_3() {
  cat > "${STUB_BIN}/vulture" <<'EOF'
#!/usr/bin/env bash
echo "vulture $*" >> "${CALLS_LOG}"
echo "unused function 'demo'"
exit 3
EOF
  chmod +x "${STUB_BIN}/vulture"
}

stub_vulture_exit_2() {
  cat > "${STUB_BIN}/vulture" <<'EOF'
#!/usr/bin/env bash
echo "vulture $*" >> "${CALLS_LOG}"
exit 2
EOF
  chmod +x "${STUB_BIN}/vulture"
}

stub_radon_ok() {
  cat > "${STUB_BIN}/radon" <<'EOF'
#!/usr/bin/env bash
echo "radon $*" >> "${CALLS_LOG}"
echo "src/teller/sample.py - A (1)"
exit 0
EOF
  chmod +x "${STUB_BIN}/radon"
}

stub_xenon_ok() {
  cat > "${STUB_BIN}/xenon" <<'EOF'
#!/usr/bin/env bash
echo "xenon $*" >> "${CALLS_LOG}"
echo "xenon-ok"
exit 0
EOF
  chmod +x "${STUB_BIN}/xenon"
}

stub_xenon_threshold_fail() {
  cat > "${STUB_BIN}/xenon" <<'EOF'
#!/usr/bin/env bash
echo "xenon $*" >> "${CALLS_LOG}"
echo "xenon-threshold-fail"
exit 1
EOF
  chmod +x "${STUB_BIN}/xenon"
}

stub_periphery_clean() {
  cat > "${STUB_BIN}/periphery" <<'EOF'
#!/usr/bin/env bash
echo "periphery $*" >> "${CALLS_LOG}"
echo "periphery-clean"
exit 0
EOF
  chmod +x "${STUB_BIN}/periphery"
}

stub_periphery_findings() {
  cat > "${STUB_BIN}/periphery" <<'EOF'
#!/usr/bin/env bash
echo "periphery $*" >> "${CALLS_LOG}"
echo "warning: unused declaration 'ghostFunction'"
exit 1
EOF
  chmod +x "${STUB_BIN}/periphery"
}

stub_lizard_ok() {
  cat > "${STUB_BIN}/lizard" <<'EOF'
#!/usr/bin/env bash
echo "lizard $*" >> "${CALLS_LOG}"
echo "Swift/sample.swift::sampleFunc CCN=1"
exit 0
EOF
  chmod +x "${STUB_BIN}/lizard"
}

stub_lizard_threshold_fail() {
  cat > "${STUB_BIN}/lizard" <<'EOF'
#!/usr/bin/env bash
echo "lizard $*" >> "${CALLS_LOG}"
echo "Swift/sample.swift::complexFunc CCN=42 -- threshold violation"
exit 1
EOF
  chmod +x "${STUB_BIN}/lizard"
}

stub_swift_tools_clean() {
  stub_periphery_clean
  stub_lizard_ok
}

@test "runs from cwd outside repo and resolves report paths" {
  #R001-T01
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_ok
  stub_swift_tools_clean
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run bash -c "cd '${TEST_TMPDIR}/elsewhere' && exec bash '${FIXTURE_ROOT}/t00_run_code_quality_tests.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/quality/reports/code-quality-summary.json" ]
  [[ "$output" == *"PASS: Code quality checks completed."* ]]
}

@test "supports tool skip mode with custom report directory" {
  #R005-T01
  run env RUN_VULTURE=false RUN_RADON=false RUN_XENON=false RUN_PERIPHERY=false RUN_LIZARD=false QUALITY_REPORT_DIR="${FIXTURE_ROOT}/.custom-quality-reports" \
    bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.custom-quality-reports/vulture.txt" ]
  [ -f "${FIXTURE_ROOT}/.custom-quality-reports/radon.txt" ]
  [ -f "${FIXTURE_ROOT}/.custom-quality-reports/xenon.txt" ]
  [ -f "${FIXTURE_ROOT}/.custom-quality-reports/periphery.txt" ]
  [ -f "${FIXTURE_ROOT}/.custom-quality-reports/lizard.txt" ]
  [ -f "${FIXTURE_ROOT}/.custom-quality-reports/code-quality-summary.json" ]
}

@test "Vulture findings fail quality gate by default" {
  #R010-T01
  stub_vulture_findings
  stub_radon_ok
  stub_xenon_ok
  stub_swift_tools_clean
  run bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: Code quality gate failed."* ]]
}

@test "Vulture findings can be non-blocking when policy override is set" {
  #R010-T02
  stub_vulture_findings
  stub_radon_ok
  stub_xenon_ok
  stub_swift_tools_clean
  run env FAIL_ON_QUALITY_ISSUES=false bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Code quality checks completed."* ]]
}

@test "Vulture exit code 3 is treated as findings not execution failure" {
  #R010-T04
  stub_vulture_findings_exit_3
  stub_radon_ok
  stub_xenon_ok
  stub_swift_tools_clean
  run bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: Code quality gate failed."* ]]
  [[ "$output" != *"ERROR: Vulture failed to execute."* ]]
}

@test "Vulture execution failure exits non-zero" {
  #R010-T03
  stub_vulture_exit_2
  stub_radon_ok
  stub_xenon_ok
  stub_swift_tools_clean
  run bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: Vulture failed to execute."* ]]
}

@test "Radon runs with configured exclude policy and writes report" {
  #R015-T01
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_ok
  stub_swift_tools_clean
  run env RADON_EXCLUDE="foo,bar" bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"radon cc ./src/teller ./src/scripts ./tests -s -a --exclude foo,bar"* ]]
  [ -f "${FIXTURE_ROOT}/artifacts/quality/reports/radon.txt" ]
}

@test "Xenon threshold violations fail quality gate by default" {
  #R020-T01
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_threshold_fail
  stub_swift_tools_clean
  run bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: Code quality gate failed."* ]]
}

@test "Xenon threshold violations can be allowed by policy override" {
  #R020-T02
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_threshold_fail
  stub_swift_tools_clean
  run env FAIL_ON_QUALITY_ISSUES=false bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
}

@test "Periphery findings fail quality gate by default (block)" {
  #R030-T01
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_ok
  stub_periphery_findings
  stub_lizard_ok
  run bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: Code quality gate failed."* ]]
}

@test "Periphery findings do not gate when gate mode is explicitly warn" {
  #R030-T02
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_ok
  stub_periphery_findings
  stub_lizard_ok
  run env PERIPHERY_GATE_MODE=warn bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Code quality checks completed."* ]]
  [[ "$output" == *"unused declaration 'ghostFunction'"* ]]
}

@test "Periphery findings allowed by policy override with default block mode" {
  #R030-T03
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_ok
  stub_periphery_findings
  stub_lizard_ok
  run env FAIL_ON_QUALITY_ISSUES=false \
    bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Code quality checks completed."* ]]
}

@test "Lizard threshold violations fail quality gate by default (block)" {
  #R035-T01
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_ok
  stub_periphery_clean
  stub_lizard_threshold_fail
  run bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: Code quality gate failed."* ]]
}

@test "Lizard threshold violations do not gate when gate mode is explicitly warn" {
  #R035-T02
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_ok
  stub_periphery_clean
  stub_lizard_threshold_fail
  run env LIZARD_GATE_MODE=warn bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Code quality checks completed."* ]]
  [[ "$output" == *"complexFunc CCN=42"* ]]
}

@test "Lizard threshold violations allowed by policy override with default block mode" {
  #R035-T03
  stub_vulture_clean
  stub_radon_ok
  stub_xenon_ok
  stub_periphery_clean
  stub_lizard_threshold_fail
  run env FAIL_ON_QUALITY_ISSUES=false \
    bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
}

@test "prints vulture radon xenon periphery and lizard details to console output" {
  #R025-T01
  stub_vulture_findings
  stub_radon_ok
  stub_xenon_threshold_fail
  stub_periphery_findings
  stub_lizard_threshold_fail
  run env FAIL_ON_QUALITY_ISSUES=false bash "${FIXTURE_ROOT}/t00_run_code_quality_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vulture details:"* ]]
  [[ "$output" == *"unused function 'demo'"* ]]
  [[ "$output" == *"Radon details:"* ]]
  [[ "$output" == *"src/teller/sample.py - A (1)"* ]]
  [[ "$output" == *"Xenon details:"* ]]
  [[ "$output" == *"xenon-threshold-fail"* ]]
  [[ "$output" == *"Periphery details:"* ]]
  [[ "$output" == *"unused declaration 'ghostFunction'"* ]]
  [[ "$output" == *"Lizard details:"* ]]
  [[ "$output" == *"complexFunc CCN=42"* ]]
}
