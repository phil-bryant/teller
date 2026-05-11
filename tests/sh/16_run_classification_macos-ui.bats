#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "16_run_classification_macos-ui.sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui"
}

teardown() {
  teardown_shell_test
}

@test "forwards args to swift run with computed package path" {
  #R001 #R005 #R010
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo "swift \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env PATH="${STUB_BIN}:${PATH}" "${FIXTURE_ROOT}/16_run_classification_macos-ui.sh" --api-url http://127.0.0.1:8787 --dry-run
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"swift run --package-path"* ]]
  [[ "$calls" == *"TransactionClassifier --api-url http://127.0.0.1:8787 --dry-run"* ]]
  [[ "$calls" == *"/macos-ui"* ]]
}
