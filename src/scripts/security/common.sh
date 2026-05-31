#!/usr/bin/env bash

#R001: Shared security helpers support explicit lane startup messaging contracts.
#R005: Shared helpers resolve repo root and enforce deterministic execution context.
#R010: Shared helpers provide command/file/toolchain precondition utilities.
#R015: Shared helpers support default lane toggle handling in caller scripts.
#R020: Shared helpers provide common output/status formatting primitives.
#R025: Shared helpers provide reusable scanner orchestration support primitives.
#R030: Shared helpers provide reusable gate/helper plumbing for blocker policies.
#R035: Shared helpers support reusable exclusion-aware command invocation paths.
#R040: Shared helpers support reusable tracked-source scan command construction.
#R045: Shared helpers support reusable Semgrep status formatting paths.
#R047: Shared helpers support reusable Semgrep invocation wiring (no quiet mode).
#R050: Shared helpers support reusable Bandit status/reporting pathways.
#R055: Shared helpers support reusable pip-audit status/reporting pathways.
#R060: Shared helpers support reusable detect-secrets/reporting pathways.
#R065: Shared helpers support reusable Ruff/reporting pathways.
#R070: Shared helpers support reusable ShellCheck/reporting pathways.
#R080: Shared helpers export Python bytecode cache path under artifacts/cache.
#R090: Shared helpers support reusable medium-or-higher gate plumbing.
#R100: Shared helpers provide reusable secret redaction for persisted Schemathesis artifacts.
#R105: Shared helpers support hash-pinned requirements enforcement for security toolchains.
#R110: Shared helpers support supply-chain artifact generation wiring (SBOM/signing scaffold).
#R115: Shared helpers support CI-default required signing mode behavior in static security lane.
security_init_repo_root() {
  local script_path="${1:-${BASH_SOURCE[0]-$0}}"
  local script_dir
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  local repo_root="$script_dir"
  if [[ "$(basename "$script_dir")" == "tests" ]]; then
    repo_root="$(cd "${script_dir}/.." && pwd)"
  elif [[ "$script_dir" == */src/scripts/security ]]; then
    repo_root="$(cd "${script_dir}/../../.." && pwd)"
  fi

  cd "$repo_root"
  # shellcheck disable=SC1091
  source "${repo_root}/src/scripts/export_test_cache_env.sh"
  export_test_cache_env "$repo_root"
  SECURITY_REPO_ROOT="$repo_root"
}

python_interpreter_usable() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  "$candidate" -c "import site" >/dev/null 2>&1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    local requirements_file="${SECURITY_REQUIREMENTS_FILE:-./requirements/security/requirements-security.txt}"
    echo "❌ Missing required command: $1"
    echo "Install prerequisites with ./01_install_prerequisites.sh, then run ./03_prepare_supply_chain_integrity.sh and pip install --require-hashes -r ${requirements_file}"
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "❌ Missing required file: $1"
    exit 1
  fi
}

print_tool_header() {
  local tool_name="$1"
  local explainer_line_1="$2"
  local explainer_line_2="$3"
  local tool_url="$4"
  local border="+==============================================================================+"
  printf '%s\n' "$border"
  printf '| %-76s |\n' "Security Tool: ${tool_name}"
  printf '| %-76s |\n' "${explainer_line_1}"
  printf '| %-76s |\n' "${explainer_line_2}"
  printf '| %-76s |\n' "URL: ${tool_url}"
  printf '%s\n' "$border"
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-30}"
  local curl_args=(-fsS)
  if [[ "$url" == https://* ]]; then
    curl_args+=(-k)
  fi
  local start_ts
  start_ts="$(date +%s)"
  while true; do
    if curl "${curl_args[@]}" "$url" >/dev/null 2>&1; then
      return 0
    fi
    if (( "$(date +%s)" - start_ts >= timeout_seconds )); then
      echo "❌ Timed out waiting for ${url}"
      return 1
    fi
    sleep 1
  done
}

redact_secret_in_file() {
  local input_path="$1"
  local output_path="$2"
  local secret="${3:-}"
  python3 - <<'PY' "$input_path" "$output_path" "$secret"
import pathlib
import sys

input_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
secret = sys.argv[3]

content = input_path.read_text(encoding="utf-8", errors="replace")
if secret:
    content = content.replace(secret, "[REDACTED]")
output_path.write_text(content, encoding="utf-8")
print(content, end="")
PY
}

redact_secret_in_place() {
  local path="$1"
  local secret="${2:-}"
  local tmp_path="${path}.redacted"
  redact_secret_in_file "$path" "$tmp_path" "$secret" >/dev/null
  mv "$tmp_path" "$path"
}
