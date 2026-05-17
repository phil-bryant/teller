#!/usr/bin/env bats

# Requirement test-case tags for requirements/05_run_av_checks-requirements.md
# #R035-T02: Traceability anchor.
# #R035-T03: Traceability anchor.

# Traceability numbered tags for requirements/05_run_av_checks-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.

load "helpers/common.bash"

copy_av_project_files() {
  create_repo_fixture
  copy_script_to_fixture "05_run_av_checks.sh"
  mkdir -p "${FIXTURE_ROOT}/teller"
  echo "safe" > "${FIXTURE_ROOT}/teller/safe.txt"
}

stub_clamscan_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 0
OUT
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_clamscan_infected() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
./bad.bin: Eicar-Test-Signature FOUND
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 1
OUT
exit 1
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_clamscan_exit_2() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_clamscan_slow_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
sleep 2
cat <<'OUT'
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 0
OUT
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_clamscan_missing_db_then_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "clamscan $*" >> "${CALLS_LOG}"
state="${TEST_TMPDIR}/clamscan-state"
if [[ ! -f "$state" ]]; then
  cat <<'OUT'
LibClamAV Error: cli_loaddbdir: No supported database files found in /opt/homebrew/var/lib/clamav
ERROR: Can't open file or directory

----------- SCAN SUMMARY -----------
Known viruses: 0
Engine version: 1.0
Scanned files: 0
Infected files: 0
OUT
  : > "$state"
  exit 2
fi
cat <<'OUT'
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 0
OUT
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_freshclam_ok() {
  cat > "${STUB_BIN}/freshclam" <<'EOF'
#!/usr/bin/env bash
echo "freshclam $*" >> "${CALLS_LOG}"
echo "Database updated"
exit 0
EOF
  chmod +x "${STUB_BIN}/freshclam"
}

teardown() {
  teardown_shell_test
}

@test "runs with cwd outside repo; paths resolve to script root" {
  #R001
  setup_shell_test
  copy_av_project_files
  stub_clamscan_clean
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run bash -c "cd '${TEST_TMPDIR}/elsewhere' && exec bash '${FIXTURE_ROOT}/05_run_av_checks.sh'"
  [ "$status" -eq 0 ]
  [ -d "${FIXTURE_ROOT}/.security-reports" ]
  [[ "$output" == *"Antivirus (AV) checks completed"* ]]
}

@test "supports skip mode and custom report directory" {
  #R005
  setup_shell_test
  copy_av_project_files
  run env RUN_CLAMAV=false SECURITY_REPORT_DIR="${FIXTURE_ROOT}/.custom-av-reports" \
    bash "${FIXTURE_ROOT}/05_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.custom-av-reports/clamav-summary.json" ]
  [ -f "${FIXTURE_ROOT}/.custom-av-reports/clamav.log" ]
  [[ "$output" == *"ClamAV repository scan skipped"* ]]
}

@test "runs ClamAV and writes report artifacts with boxed header" {
  #R010 #R030
  setup_shell_test
  copy_av_project_files
  stub_clamscan_clean
  run bash "${FIXTURE_ROOT}/05_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/clamav.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/clamav-summary.json" ]
  [[ "$output" == *"+==============================================================================+"* ]]
  [[ "$output" == *"Security Tool: ClamAV"* ]]
  [[ "$output" == *"URL: https://www.clamav.net/"* ]]
}

@test "prints signature freshness, target path, and heartbeat during long scan" {
  #R015 #R020
  setup_shell_test
  copy_av_project_files
  stub_clamscan_slow_clean
  run env CLAMAV_HEARTBEAT_SECONDS=1 CLAMAV_SCAN_TARGET="./teller" \
    bash "${FIXTURE_ROOT}/05_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ClamAV signature freshness"* ]]
  [[ "$output" == *"ClamAV scan target:"*"/teller"* ]]
  [[ "$output" == *"ClamAV scan in progress"* ]]
}

@test "refreshes signatures with freshclam when database is missing and retries scan" {
  #R025
  setup_shell_test
  copy_av_project_files
  stub_clamscan_missing_db_then_clean
  stub_freshclam_ok
  run bash "${FIXTURE_ROOT}/05_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attempting one-time database refresh with freshclam"* ]]
  [[ "$output" == *"Retrying ClamAV repository scan after signature refresh"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"freshclam --stdout"* ]]
}

@test "fails AV gate on infected files by default and supports override" {
  #R035
  setup_shell_test
  copy_av_project_files
  stub_clamscan_infected
  run bash "${FIXTURE_ROOT}/05_run_av_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Antivirus (AV) gate failed"* ]]

  run env AV_FAIL_ON_INFECTED=false \
    bash "${FIXTURE_ROOT}/05_run_av_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Antivirus (AV) checks completed"* ]]
}

@test "ClamAV exit code greater than 1 is an execution failure" {
  #R010
  setup_shell_test
  copy_av_project_files
  stub_clamscan_exit_2
  run bash "${FIXTURE_ROOT}/05_run_av_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ClamAV failed to execute."* ]]
}
