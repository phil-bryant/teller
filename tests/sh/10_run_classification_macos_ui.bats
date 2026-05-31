#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/10_run_classification_macos_ui.sh"
}

@test "uses strict shell mode" {
  #R001
  run grep "set -euo pipefail" "$(src)"
  [ "$status" -eq 0 ]
}

@test "builds debug TransactionClassifier and launches binary" {
  #R005 #R005-T01 #R010 #R010-T01
  run grep "swift build --package-path" "$(src)"
  [ "$status" -eq 0 ]
  run grep '\.build/debug/TransactionClassifier' "$(src)"
  [ "$status" -eq 0 ]
  run grep '#app_args\[@\]' "$(src)"
  [ "$status" -eq 0 ]
}

@test "profile flag enables transaction list profiling env" {
  #R015 #R015-T01
  run grep 'TELLER_UI_PROFILE_TRANSACTION_LIST=true' "$(src)"
  [ "$status" -eq 0 ]
  run grep -- '--profile' "$(src)"
  [ "$status" -eq 0 ]
}

@test "help documents profile flag" {
  #R015 #R015-T02
  run grep 'usage:.*--profile' "$(src)"
  [ "$status" -eq 0 ]
}

@test "supports launch with no forwarded args under nounset" {
  #R010 #R010-T02
  run grep '\${#app_args\[@\]} > 0' "$(src)"
  [ "$status" -eq 0 ]
  run grep 'env "${launch_env\[@\]}" "\$binary" &' "$(src)"
  [ "$status" -eq 0 ]
}

@test "exits non-zero when swift build fails" {
  #R001 #R001-T01
  setup_shell_test
  create_repo_fixture
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui"
  copy_script_to_fixture "10_run_classification_macos_ui.sh"
  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_BIN}/swift"
  run bash -c "cd '${FIXTURE_ROOT}' && PATH='${STUB_BIN}':\"\$PATH\" ./10_run_classification_macos_ui.sh"
  [ "$status" -eq 1 ]
}
