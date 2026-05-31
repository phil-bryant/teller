#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "t02_run_dependency_freshness_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
}

teardown() {
  teardown_shell_test
}

@test "runs from repo root and writes freshness artifacts" {
  #R001-T01 #R005-T01 #R005-T02 #R010-T01 #R010-T02 #R010-T03 #R010-T04 #R012-T01 #R020-T01 #R025-T01 #R025-T02 #R025-T03 #R030-T01 #R030-T02 #R032-T01
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python cwd=\$(pwd) args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  cat > "${FIXTURE_ROOT}/artifacts/venv/security/bin/python" <<EOF
#!/usr/bin/env bash
echo "security-python cwd=\$(pwd) args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${TEST_TMPDIR}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' '${FIXTURE_ROOT}/t02_run_dependency_freshness_tests.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/dependency-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/dependency-freshness.txt" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/security-toolchain-dependency-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/security-toolchain-dependency-freshness.txt" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/binary-integrity.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/binary-integrity.txt" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/teller-api-version-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/teller-api-version-freshness.txt" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./src/scripts/check_dependency_freshness.py"* ]]
  [[ "$calls" == *"--fail-on-any-actionable-outdated"* ]]
  [[ "$calls" == *"--fail-on-direct-outdated"* ]]
  [[ "$calls" == *"--fail-on-venv-cruft"* ]]
  [[ "$calls" == *"args=./src/scripts/check_binary_integrity.py --policy ./config/security/binary-integrity-policy.json"* ]]
  [[ "$calls" == *"--output-json ./artifacts/security/binary-integrity.json --output-text ./artifacts/security/binary-integrity.txt --fail-on-missing-required --fail-on-version --fail-on-hash"* ]]
  [[ "$calls" == *"security-python cwd=${FIXTURE_ROOT} args=./src/scripts/check_dependency_freshness.py --requirements ./requirements/security/requirements-security.txt"* ]]
  [[ "$calls" == *"--output-json ./artifacts/security/security-toolchain-dependency-freshness.json --output-text ./artifacts/security/security-toolchain-dependency-freshness.txt"* ]]
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./src/scripts/check_teller_api_version_freshness.py"* ]]
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./src/scripts/check_postgres_freshness.py"* ]]
  [[ "$calls" == *"--check-server-version --server-psql-args -h localhost -U teller -d prod"* ]]
  [[ "$calls" == *"--check-cves --cve-snapshot ./config/security/postgres-cve-snapshot.json --cve-policy ./config/security/postgres-cve-policy.json"* ]]
  [[ "$calls" == *"--refresh-cve-snapshot"* ]]
  [[ "$calls" == *"--fail-on-cve"* ]]
}

@test "keeps direct dependency freshness gate strict despite permissive env overrides" {
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  cat > "${FIXTURE_ROOT}/artifacts/venv/security/bin/python" <<EOF
#!/usr/bin/env bash
echo "security-python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false DEPENDENCY_FAIL_ON_DIRECT_OUTDATED=false DEPENDENCY_DIRECT_OUTDATED_IGNORE='fastapi,hypothesis,starlette' ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"./src/scripts/check_dependency_freshness.py"* ]]
  [[ "$calls" == *"--fail-on-any-actionable-outdated"* ]]
  [[ "$calls" == *"--fail-on-direct-outdated"* ]]
  [[ "$calls" == *"--fail-on-venv-cruft"* ]]
  [[ "$calls" == *"security-python args=./src/scripts/check_dependency_freshness.py --requirements ./requirements/security/requirements-security.txt"* ]]
  [[ "$calls" != *"--direct-outdated-ignore"* ]]
}

@test "always passes strict freshness flags" {
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  cat > "${FIXTURE_ROOT}/artifacts/venv/security/bin/python" <<EOF
#!/usr/bin/env bash
echo "security-python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false DEPENDENCY_FAIL_ON_MAJOR=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"--fail-on-any-actionable-outdated"* ]]
  [[ "$calls" == *"--fail-on-direct-outdated"* ]]
  [[ "$calls" == *"--fail-on-venv-cruft"* ]]
  [[ "$calls" == *"security-python args=./src/scripts/check_dependency_freshness.py --requirements ./requirements/security/requirements-security.txt"* ]]
  [[ "$calls" != *"--fail-on-major"* ]]
}

@test "falls back to python3 when security toolchain interpreter is unusable" {
  #R030-T03
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "runtime-python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<EOF
#!/usr/bin/env python3
import pathlib
import sys

log_path = pathlib.Path("${CALLS_LOG}")
log_path.parent.mkdir(parents=True, exist_ok=True)
log_path.write_text(log_path.read_text(encoding="utf-8") + f"security-exec={sys.executable} args={' '.join(sys.argv[1:])}\\n" if log_path.exists() else f"security-exec={sys.executable} args={' '.join(sys.argv[1:])}\\n", encoding="utf-8")
args = sys.argv[1:]
for idx, token in enumerate(args):
    if token == "--output-json" and idx + 1 < len(args):
        pathlib.Path(args[idx + 1]).write_text("{}\\n", encoding="utf-8")
    if token == "--output-text" and idx + 1 < len(args):
        pathlib.Path(args[idx + 1]).write_text("ok\\n", encoding="utf-8")
EOF
  cat > "${FIXTURE_ROOT}/src/scripts/check_binary_integrity.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_VERSION_FRESHNESS=false RUN_POSTGRES_FRESHNESS=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Security toolchain interpreter './artifacts/venv/security/bin/python' is not usable; falling back to python3"* ]]
  [ -f "${FIXTURE_ROOT}/artifacts/security/security-toolchain-dependency-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/security-toolchain-dependency-freshness.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"runtime-python args=./src/scripts/check_dependency_freshness.py"* ]]
  [[ "$calls" == *"security-exec="* ]]
  [[ "$calls" == *"--requirements ./requirements/security/requirements-security.txt"* ]]
  [[ "$calls" == *"args=./src/scripts/check_binary_integrity.py --policy ./config/security/binary-integrity-policy.json"* ]]
}

@test "skips binary integrity lane when disabled" {
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  cat > "${FIXTURE_ROOT}/artifacts/venv/security/bin/python" <<EOF
#!/usr/bin/env bash
echo "security-python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_BINARY_INTEGRITY_CHECK=false RUN_POSTGRES_FRESHNESS=false RUN_TELLER_VERSION_FRESHNESS=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security/binary-integrity.json" ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security/binary-integrity.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"./src/scripts/check_binary_integrity.py"* ]]
}

@test "fails fast for non-executable explicit interpreter path" {
  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON=./missing-python ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Project python not executable"* ]]
}

@test "skips PostgreSQL freshness lane when disabled" {
  #R020-T02 #R020-T03
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.json" ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"./src/scripts/check_postgres_freshness.py"* ]]
}

@test "skips Teller API version freshness lane when disabled" {
  #R015-T01 #R015-T02
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_VERSION_FRESHNESS=false RUN_POSTGRES_FRESHNESS=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"./src/scripts/check_teller_api_version_freshness.py"* ]]
}

@test "prints PostgreSQL server-check target diagnostics for explicit args" {
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' POSTGRES_SERVER_PSQL_ARGS='-h dbhost -U teller -d prod' ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PostgreSQL server check target: psql args (explicit)"* ]]
}

@test "omits PostgreSQL CVE args when disabled" {
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' POSTGRES_CHECK_CVES=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"./src/scripts/check_postgres_freshness.py"* ]]
  [[ "$calls" != *"--check-cves"* ]]
  [[ "$calls" != *"--cve-snapshot"* ]]
  [[ "$calls" != *"--cve-policy"* ]]
}
