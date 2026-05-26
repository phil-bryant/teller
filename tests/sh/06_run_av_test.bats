#!/usr/bin/env bats
load "helpers/common.bash"

copy_av_project_files() {
  create_repo_fixture
  copy_script_to_fixture "06_run_av_test.sh"
  mkdir -p "${FIXTURE_ROOT}/src/teller"
  echo "safe" > "${FIXTURE_ROOT}/src/teller/safe.txt"
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

stub_clamscan_requires_ui_artifact_exclude() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
has_ui_exclude=false
for arg in "$@"; do
  if [[ "$arg" == "--exclude-dir=artifacts/macos-ui-regression(/|$)" ]]; then
    has_ui_exclude=true
    break
  fi
done
if [[ "$has_ui_exclude" != "true" ]]; then
  echo "WARNING: Can't open file ./artifacts/macos-ui-regression/xcuitest-results.xcresult/Data/refs.0~broken: No such file or directory"
  cat <<'OUT'
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 0
Total errors: 1
OUT
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
  #R001-T01
  setup_shell_test
  copy_av_project_files
  stub_clamscan_clean
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run bash -c "cd '${TEST_TMPDIR}/elsewhere' && exec bash '${FIXTURE_ROOT}/06_run_av_test.sh'"
  [ "$status" -eq 0 ]
  [ -d "${FIXTURE_ROOT}/artifacts/security/reports" ]
  [[ "$output" == *"Antivirus (AV) checks completed"* ]]
}

@test "supports skip mode and custom report directory" {
  #R005-T01
  setup_shell_test
  copy_av_project_files
  run env RUN_CLAMAV=false SECURITY_REPORT_DIR="${FIXTURE_ROOT}/.custom-av-reports" \
    bash "${FIXTURE_ROOT}/06_run_av_test.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.custom-av-reports/clamav-summary.json" ]
  [ -f "${FIXTURE_ROOT}/.custom-av-reports/clamav.log" ]
  [[ "$output" == *"ClamAV repository scan skipped"* ]]
}

@test "runs ClamAV and writes report artifacts with boxed header" {
  #R010-T01 #R030-T01
  setup_shell_test
  copy_av_project_files
  stub_clamscan_clean
  run bash "${FIXTURE_ROOT}/06_run_av_test.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/reports/clamav.log" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/reports/clamav-summary.json" ]
  [[ "$output" == *"+==============================================================================+"* ]]
  [[ "$output" == *"Security Tool: ClamAV"* ]]
  [[ "$output" == *"URL: https://www.clamav.net/"* ]]
}

@test "prints signature freshness, target path, and heartbeat during long scan" {
  #R015-T01 #R020-T01
  setup_shell_test
  copy_av_project_files
  stub_clamscan_slow_clean
  run env CLAMAV_HEARTBEAT_SECONDS=1 CLAMAV_SCAN_TARGET="./src/teller" \
    bash "${FIXTURE_ROOT}/06_run_av_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ClamAV signature freshness"* ]]
  [[ "$output" == *"ClamAV scan target:"*"/src/teller"* ]]
  [[ "$output" == *"ClamAV scan in progress"* ]]
}

@test "excludes macos ui regression artifacts from ClamAV scan" {
  setup_shell_test
  copy_av_project_files
  mkdir -p "${FIXTURE_ROOT}/artifacts/macos-ui-regression/xcuitest-results.xcresult/Data"
  ln -sf "./missing-data-blob" "${FIXTURE_ROOT}/artifacts/macos-ui-regression/xcuitest-results.xcresult/Data/refs.0~broken"
  stub_clamscan_requires_ui_artifact_exclude
  run bash "${FIXTURE_ROOT}/06_run_av_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Antivirus (AV) checks completed"* ]]
}

@test "refreshes signatures with freshclam when database is missing and retries scan" {
  #R025-T01
  setup_shell_test
  copy_av_project_files
  stub_clamscan_missing_db_then_clean
  stub_freshclam_ok
  run bash "${FIXTURE_ROOT}/06_run_av_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attempting one-time database refresh with freshclam"* ]]
  [[ "$output" == *"Retrying ClamAV repository scan after signature refresh"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"freshclam --stdout"* ]]
}

@test "fails AV gate on infected files by default and supports override" {
  #R035-T01 #R035-T02 #R035-T03
  setup_shell_test
  copy_av_project_files
  stub_clamscan_infected
  run bash "${FIXTURE_ROOT}/06_run_av_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Antivirus (AV) gate failed"* ]]

  run env AV_FAIL_ON_INFECTED=false \
    bash "${FIXTURE_ROOT}/06_run_av_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Antivirus (AV) checks completed"* ]]
}

@test "ClamAV exit code greater than 1 is an execution failure" {
  setup_shell_test
  copy_av_project_files
  stub_clamscan_exit_2
  run bash "${FIXTURE_ROOT}/06_run_av_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ClamAV failed to execute."* ]]
}
