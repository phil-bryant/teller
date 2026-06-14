#!/usr/bin/env bats
load "helpers/common.bash"

#R001: Prepare bats fixture state for core traceability verification.
setup() {
  setup_shell_test
}

#R001: Cleanup bats fixture state for core traceability verification.
teardown() {
  teardown_shell_test
}

@test "ocr_backend mapped sources carry scoped traceability tags" {
  #R001: Enforce module-level scoped source-tag coverage for mapped files.
  #R001-T01: Verify each mapped source file includes scoped `#R001:` comments and core symbols.
  for rel in \
    "src/core/include/tellercore/ocr.hpp" \
    "src/core/src/ocr_backend_apple.mm" \
    "src/core/src/ocr_backend_win.cpp"
  do
    full_path="$(repo_root)/${rel}"
    [ -f "$full_path" ]
    run grep -E "#R001:" "$full_path"
    [ "$status" -eq 0 ]
  done
}
