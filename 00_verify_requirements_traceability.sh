#!/bin/bash
#R001: Use strict mode and temp files for deterministic comparisons.
umask 007
set -euo pipefail

list_requirements_files() {
    python3 - <<'PY'
import os
base = "requirements"
paths = []
for root, _dirs, files in os.walk(base):
    for name in files:
        if name.endswith("-requirements.md"):
            paths.append(os.path.join(root, name))
for path in sorted(set(paths)):
    print(path)
PY
}

extract_requirement_ids() {
    local requirements_file="$1" out_file="$2"
    awk 'match($0, /^R[0-9]{3}(-[0-9]{3})*/) { print substr($0, RSTART, RLENGTH) }' "$requirements_file" | sort -u > "$out_file"
}

extract_source_ids() {
    local source_file="$1" out_file="$2"
    awk '{
        while (match($0, /#R[0-9]{3}(-[0-9]{3})*/)) {
            id = substr($0, RSTART + 1, RLENGTH - 1)
            print id
            $0 = substr($0, RSTART + RLENGTH)
        }
    }' "$source_file" | sort -u > "$out_file"
}

extract_test_ids() {
    local test_file="$1" out_file="$2"
    extract_source_ids "$test_file" "$out_file"
}

extract_source_files_from_requirements() {
    local requirements_file="$1" out_file="$2"
    awk '
        /^## Scope$/ { in_scope = 1; next }
        /^## / && in_scope { in_scope = 0 }
        /^R[0-9]{3}(-[0-9]{3})*/ && in_scope { in_scope = 0 }
        !in_scope { next }
        {
            line = $0
            while (match(line, /`[^`]+`/)) {
                token = substr(line, RSTART + 1, RLENGTH - 2)
                sub(/^\.\//, "", token)
                if (token ~ /^[A-Za-z0-9._\/-]+\.(sh|py|swift|sql)$/) {
                    print token
                }
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$requirements_file" | sort -u > "$out_file"
}

extract_source_files_from_analogous_tree() {
    local requirements_file="$1" out_file="$2"
    local rel_path req_dir req_base source_stem search_root
    rel_path="${requirements_file#requirements/}"
    req_base="$(basename "$rel_path")"
    source_stem="${req_base%-requirements.md}"
    if [ "$source_stem" = "$req_base" ]; then
        : > "$out_file"
        return 0
    fi
    req_dir="$(dirname "$rel_path")"
    if [ "$req_dir" = "." ]; then
        search_root="."
    else
        search_root="$req_dir"
    fi
    python3 - "$search_root" "$source_stem" > "$out_file" <<'PY'
import os
import sys

search_root = sys.argv[1]
stem = sys.argv[2]
allowed_exts = {"sh", "py", "swift", "sql"}
matches = []

if os.path.isdir(search_root):
    for root, _dirs, files in os.walk(search_root):
        for name in files:
            base, dot, ext = name.rpartition(".")
            if not dot:
                continue
            if base == stem and ext in allowed_exts:
                matches.append(os.path.join(root, name))

for path in sorted(set(matches)):
    print(path)
PY
}

extract_ui_required_ids() {
    local requirements_file="$1" out_file="$2"
    awk '
        {
            line = tolower($0)
            if (match(line, /^r[0-9]{3}(-[0-9]{3})*[[:space:]]+statement:/)) {
                rid = toupper($1)
                if (line ~ /ui[[:space:]-]*test/ || line ~ /xcuitest/ || line ~ /xctest[[:space:]-]*ui/ || line ~ /ui[[:space:]-]*mode/) {
                    print rid
                }
            }
        }
    ' "$requirements_file" | sort -u > "$out_file"
}

discover_test_files_for_requirements() {
    local requirements_file="$1" source_list_file="$2" default_tests_file="$3" ui_tests_file="$4"
    python3 - "$requirements_file" "$source_list_file" "$default_tests_file" "$ui_tests_file" <<'PY'
import os
import sys

requirements_file = sys.argv[1]
source_list_file = sys.argv[2]
default_tests_file = sys.argv[3]
ui_tests_file = sys.argv[4]

repo_root = os.getcwd()
if os.path.isabs(requirements_file):
    try:
        requirements_file = os.path.relpath(requirements_file, repo_root)
    except ValueError:
        pass

seen_default = set()
seen_ui = set()
default_results = []
ui_results = []

def add_path(path: str, lane: str) -> None:
    candidate = os.path.join(repo_root, path) if not os.path.isabs(path) else path
    if not os.path.isfile(candidate):
        return
    normalized = os.path.realpath(candidate)
    if lane == "ui":
        if normalized not in seen_ui:
            seen_ui.add(normalized)
            ui_results.append(normalized)
        return
    if normalized not in seen_default:
        seen_default.add(normalized)
        default_results.append(normalized)

def collect_swift_lane(root_dir: str, lane: str, stem: str = "") -> None:
    root_path = os.path.join(repo_root, root_dir)
    if not os.path.isdir(root_path):
        return
    for dirpath, _dirnames, filenames in os.walk(root_path):
        for filename in filenames:
            if not filename.endswith(".swift"):
                continue
            if stem and stem not in filename:
                continue
            rel = os.path.relpath(os.path.join(dirpath, filename), repo_root)
            add_path(rel, lane)

source_files = []
if os.path.isfile(source_list_file):
    with open(source_list_file, "r", encoding="utf-8") as handle:
        for raw in handle:
            value = raw.strip()
            if value:
                source_files.append(value)

for source_file in source_files:
    if os.path.isabs(source_file):
        try:
            source_file = os.path.relpath(source_file, repo_root)
        except ValueError:
            pass
    base = os.path.basename(source_file)
    stem, ext = os.path.splitext(base)
    ext = ext.lower()
    source_norm = source_file.replace("\\", "/")
    if ext == ".sh":
        add_path(f"tests/sh/{stem}.bats", "default")
    if ext == ".py":
        if source_norm.startswith("teller/"):
            add_path(f"tests/py/test_{stem}.py", "default")
        elif source_norm.startswith(tuple(f"{n:02d}_" for n in range(100))):
            add_path(f"tests/sh/{stem}.bats", "default")
    if ext == ".swift" and source_norm.startswith("macos-ui/Sources/"):
        collect_swift_lane("macos-ui/Tests", "default", stem=stem)
        collect_swift_lane("macos-ui/UITests", "ui", stem=stem)

if requirements_file.startswith("requirements/macos-ui/"):
    collect_swift_lane("macos-ui/Tests", "default")
    collect_swift_lane("macos-ui/UITests", "ui")

if requirements_file.startswith("requirements/teller/"):
    tests_py_root = os.path.join(repo_root, "tests/py")
    if os.path.isdir(tests_py_root):
        for filename in sorted(os.listdir(tests_py_root)):
            if filename.startswith("test_") and filename.endswith(".py"):
                add_path(os.path.join("tests/py", filename), "default")

if requirements_file.startswith("requirements/") and os.path.basename(requirements_file)[:2].isdigit():
    tests_sh_root = os.path.join(repo_root, "tests/sh")
    if os.path.isdir(tests_sh_root):
        prefix = os.path.basename(requirements_file)[:2] + "_"
        for filename in sorted(os.listdir(tests_sh_root)):
            if filename.startswith(prefix) and filename.endswith(".bats"):
                add_path(os.path.join("tests/sh", filename), "default")

with open(default_tests_file, "w", encoding="utf-8") as handle:
    for item in sorted(default_results):
        handle.write(f"{item}\n")

with open(ui_tests_file, "w", encoding="utf-8") as handle:
    for item in sorted(ui_results):
        handle.write(f"{item}\n")
PY
}

collect_ids_from_test_list() {
    local test_list_file="$1" out_file="$2"
    local test_file tmp_ids
    tmp_ids="$(mktemp)"
    : > "$tmp_ids"
    if [ ! -s "$test_list_file" ]; then
        : > "$out_file"
        return 0
    fi
    while IFS= read -r test_file; do
        [ -n "$test_file" ] || continue
        [ -f "$test_file" ] || continue
        local one_file_ids
        one_file_ids="$(mktemp)"
        extract_test_ids "$test_file" "$one_file_ids"
        cat "$one_file_ids" >> "$tmp_ids"
    done < "$test_list_file"
    sort -u "$tmp_ids" > "$out_file"
}

verify_requirements_test_traceability() {
    local requirements_file="$1" source_list_file="$2"
    local req_ids_file ui_req_ids_file default_tests_file ui_tests_file
    local default_test_ids_file ui_test_ids_file missing_test_ids_file
    req_ids_file="$(mktemp)"
    ui_req_ids_file="$(mktemp)"
    default_tests_file="$(mktemp)"
    ui_tests_file="$(mktemp)"
    default_test_ids_file="$(mktemp)"
    ui_test_ids_file="$(mktemp)"
    missing_test_ids_file="$(mktemp)"
    #R050: Discover test files by requirements/source conventions and test lanes.
    discover_test_files_for_requirements "$requirements_file" "$source_list_file" "$default_tests_file" "$ui_tests_file"
    #R055: Parse requirement IDs that must be covered by UI tests.
    extract_requirement_ids "$requirements_file" "$req_ids_file"
    extract_ui_required_ids "$requirements_file" "$ui_req_ids_file"
    #R060: Parse all #R tags from discovered tests in each lane.
    collect_ids_from_test_list "$default_tests_file" "$default_test_ids_file"
    collect_ids_from_test_list "$ui_tests_file" "$ui_test_ids_file"
    : > "$missing_test_ids_file"
    while IFS= read -r req_id; do
        [ -n "$req_id" ] || continue
        if awk -v id="$req_id" '$0 == id { found=1 } END { exit found ? 0 : 1 }' "$ui_req_ids_file"; then
            if ! awk -v id="$req_id" '$0 == id { found=1 } END { exit found ? 0 : 1 }' "$ui_test_ids_file"; then
                printf "%s\n" "$req_id" >> "$missing_test_ids_file"
            fi
            continue
        fi
        if awk -v id="$req_id" '$0 == id { found=1 } END { exit found ? 0 : 1 }' "$default_test_ids_file"; then
            continue
        fi
        if awk -v id="$req_id" '$0 == id { found=1 } END { exit found ? 0 : 1 }' "$ui_test_ids_file"; then
            continue
        fi
        printf "%s\n" "$req_id" >> "$missing_test_ids_file"
    done < "$req_ids_file"
    sort -u "$missing_test_ids_file" -o "$missing_test_ids_file"
    #R065: Fail when any requirement ID lacks at least one tagged test.
    if [ ! -s "$missing_test_ids_file" ]; then
        echo "✅ PASS (test-traceability): ${requirements_file}"
        return 0
    fi
    echo "❌ FAIL (test-traceability): missing tagged tests for requirement IDs in ${requirements_file}:"
    sed 's/^/  - /' "$missing_test_ids_file"
    if [ ! -s "$default_tests_file" ] && [ ! -s "$ui_tests_file" ]; then
        echo "  (no discoverable tests found for this requirements document)"
    fi
    return 1
}

is_locked_source_file() {
    local source_file="$1"
    awk '
        /^[[:space:]]*##[[:space:]]*<AI_MODEL_INSTRUCTION>[[:space:]]*$/ { a = 1 }
        /^[[:space:]]*##[[:space:]]*DO_NOT_MODIFY_THIS_FILE[[:space:]]*$/ { b = 1 }
        END { exit (a && b) ? 0 : 1 }
    ' "$source_file"
}

verify_locked_exception() {
    local requirements_file="$1" source_file="$2"
    local marker_a marker_b
    marker_a="$(awk '/<AI_MODEL_INSTRUCTION>/{ print "yes"; exit }' "$source_file")"
    marker_b="$(awk '/DO_NOT_MODIFY_THIS_FILE/{ print "yes"; exit }' "$source_file")"
    if [ "$marker_a" != "yes" ] || [ "$marker_b" != "yes" ]; then
        echo "❌ FAIL (locked-policy): ${source_file} is missing expected lock markers."
        return 1
    fi
    if ! awk '
        {
            line = tolower($0)
            if (line ~ /^r[0-9]{3}(-[0-9]{3})*[[:space:]]+statement:/ && line ~ /locked/ && line ~ /traceability/) {
                found = 1
            }
        }
        END { exit found ? 0 : 1 }
    ' "$requirements_file"; then
        echo "❌ FAIL (locked-policy): ${requirements_file} is missing locked-traceability policy requirement."
        return 1
    fi
    echo "✅ PASS (locked-policy): ${source_file} verified-with-exception."
    return 0
}

verify_strict_pair() {
    local requirements_file="$1" source_file="$2"
    local req_ids_file script_ids_file missing_ids_file extra_ids_file
    req_ids_file="$(mktemp)"
    script_ids_file="$(mktemp)"
    missing_ids_file="$(mktemp)"
    extra_ids_file="$(mktemp)"
    #R020: Parse requirement IDs from requirements file entries.
    extract_requirement_ids "$requirements_file" "$req_ids_file"
    #R025: Parse all #R tags from source content.
    extract_source_ids "$source_file" "$script_ids_file"
    #R030: Compute missing/extra ID set differences.
    comm -23 "$req_ids_file" "$script_ids_file" > "$missing_ids_file"
    comm -13 "$req_ids_file" "$script_ids_file" > "$extra_ids_file"
    #R035: Pass only when missing/extra sets are both empty.
    if [ ! -s "$missing_ids_file" ] && [ ! -s "$extra_ids_file" ]; then
        return 0
    fi
    if [ -s "$missing_ids_file" ]; then
        echo "❌ Missing #R tags for requirement IDs:"
        sed 's/^/  - /' "$missing_ids_file"
    fi
    if [ -s "$extra_ids_file" ]; then
        echo "⚠️  Extra #R tags in source not present in requirements:"
        sed 's/^/  - /' "$extra_ids_file"
    fi
    return 1
}

verify_single_pair() {
    local requirements_file="$1"
    local source_file="$2"
    echo "Traceability check"
    echo "- requirements: $requirements_file"
    echo "- source: $source_file"
    #R015: Fail clearly when requirements file is missing.
    if [ ! -f "$requirements_file" ]; then
        echo "❌ Requirements file not found: $requirements_file"
        return 1
    fi
    #R015: Fail clearly when source file is missing.
    if [ ! -f "$source_file" ]; then
        echo "❌ Source file not found: $source_file"
        return 1
    fi
    if is_locked_source_file "$source_file"; then
        verify_locked_exception "$requirements_file" "$source_file"
        return $?
    fi
    verify_strict_pair "$requirements_file" "$source_file"
}

verify_single_pair_with_tests() {
    local requirements_file="$1" source_file="$2"
    local source_list_file status=0
    source_list_file="$(mktemp)"
    printf "%s\n" "$source_file" > "$source_list_file"
    if ! verify_single_pair "$requirements_file" "$source_file"; then
        status=1
    fi
    if ! verify_requirements_test_traceability "$requirements_file" "$source_list_file"; then
        status=1
    fi
    [ "$status" -eq 0 ]
}

verify_requirements_file_sources() {
    local requirements_file="$1"
    local source_list_file source_file found_source=0 file_fail=0
    source_list_file="$(mktemp)"
    #R010: Resolve source files referenced by each requirements document.
    extract_source_files_from_requirements "$requirements_file" "$source_list_file"
    if [ ! -s "$source_list_file" ]; then
        #R010: Fallback to analogous subdirectory-tree mapping by requirements file name.
        extract_source_files_from_analogous_tree "$requirements_file" "$source_list_file"
    fi
    if [ ! -s "$source_list_file" ]; then
        #R015: Fail clearly when no source mappings are discoverable.
        echo "❌ FAIL: ${requirements_file} has no discoverable source file references."
        return 1
    fi
    while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        found_source=1
        if [ ! -f "$source_file" ]; then
            #R015: Fail clearly when a referenced source file is missing.
            echo "❌ FAIL: ${requirements_file} references missing source file ${source_file}"
            file_fail=1
            continue
        fi
        if verify_single_pair "$requirements_file" "$source_file"; then
            echo "✅ PASS: ${requirements_file} -> ${source_file}"
            echo ""
        else
            echo "❌ FAIL: ${requirements_file} -> ${source_file}"
            echo ""
            file_fail=1
        fi
    done < "$source_list_file"
    if ! verify_requirements_test_traceability "$requirements_file" "$source_list_file"; then
        file_fail=1
    fi
    if [ "$found_source" -eq 0 ]; then
        echo "❌ FAIL: ${requirements_file} has no source files to verify."
        return 1
    fi
    [ "$file_fail" -eq 0 ]
}

verify_all_requirements() {
    local total=0 pass=0 fail=0 requirements_file
    local requirements_files=()
    while IFS= read -r requirements_file; do
        requirements_files+=("$requirements_file")
    done < <(list_requirements_files)
    #R005: Discover and verify all requirements/**/*-requirements.md by default.
    if [ "${#requirements_files[@]}" -eq 0 ]; then
        echo "❌ FAIL: no requirements files found under requirements/**/*-requirements.md"
        return 1
    fi
    echo "Traceability check for all requirements/**/*-requirements.md"
    for requirements_file in "${requirements_files[@]}"; do
        total=$((total + 1))
        if verify_requirements_file_sources "$requirements_file"; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
        fi
    done
    #R040: Enforce numbered-script-to-numbered-requirements coverage completeness.
    verify_numbered_script_requirements_coverage || fail=$((fail + 1))
    #R045: Enforce numbered requirements docs map to same-numbered numbered scripts.
    verify_numbered_requirement_scope_alignment || fail=$((fail + 1))
    echo ""
    echo "Summary: total=${total} pass=${pass} fail=${fail}"
    if [ "$fail" -eq 0 ]; then
        echo "✅ All traceability checks passed."
        return 0
    fi
    echo "❌ One or more traceability checks failed."
    return 1
}

verify_numbered_script_requirements_coverage() {
    local script_file req_file num base missing script_num_file req_num_file
    missing="false"
    script_num_file="$(mktemp)"
    req_num_file="$(mktemp)"
    for script_file in [0-9][0-9]_*.sh [0-9][0-9]_*.py; do
        [ -e "$script_file" ] || continue
        num="${script_file%%_*}"
        printf "%s|%s\n" "$num" "$script_file" >> "$script_num_file"
    done
    for req_file in requirements/[0-9][0-9]_*-requirements.md; do
        [ -e "$req_file" ] || continue
        base="$(basename "$req_file")"
        num="${base%%_*}"
        printf "%s|%s\n" "$num" "$req_file" >> "$req_num_file"
    done
    sort -u "$script_num_file" -o "$script_num_file"
    sort -u "$req_num_file" -o "$req_num_file"
    while IFS='|' read -r num script_file; do
        [ -n "$num" ] || continue
        if ! awk -F'|' -v n="$num" '$1 == n { found=1 } END { exit found ? 0 : 1 }' "$req_num_file"; then
            if [ "$missing" = "false" ]; then
                echo "❌ FAIL: missing numbered requirements docs for numbered scripts:"
            fi
            echo "  - ${script_file} (expected requirements/${num}_*-requirements.md)"
            missing="true"
        fi
    done < "$script_num_file"
    if [ "$missing" = "false" ]; then
        echo "✅ PASS: numbered script coverage complete (every numbered script has a numbered requirements doc)."
        return 0
    fi
    return 1
}

verify_numbered_requirement_scope_alignment() {
    local req_file base req_num source_list_file source_file
    local found_numbered_source matched_numbered_source failed
    failed="false"
    for req_file in requirements/[0-9][0-9]_*-requirements.md; do
        [ -e "$req_file" ] || continue
        base="$(basename "$req_file")"
        req_num="${base%%_*}"
        source_list_file="$(mktemp)"
        extract_source_files_from_requirements "$req_file" "$source_list_file"
        found_numbered_source="false"
        matched_numbered_source="false"
        while IFS= read -r source_file; do
            [ -n "$source_file" ] || continue
            case "$source_file" in
                [0-9][0-9]_*.sh|[0-9][0-9]_*.py)
                    found_numbered_source="true"
                    if [ "${source_file%%_*}" = "$req_num" ]; then
                        matched_numbered_source="true"
                    fi
                    ;;
            esac
        done < "$source_list_file"
        if [ "$found_numbered_source" = "false" ] || [ "$matched_numbered_source" = "false" ]; then
            if [ "$failed" = "false" ]; then
                echo "❌ FAIL: numbered requirements scope mismatch:"
            fi
            echo "  - ${req_file} must reference a numbered source starting with ${req_num}_"
            failed="true"
        fi
    done
    if [ "$failed" = "false" ]; then
        echo "✅ PASS: numbered requirements scope alignment complete (NN requirements map to NN scripts)."
        return 0
    fi
    return 1
}

print_usage() {
    echo "Usage:"
    echo "  ./00_verify_requirements_traceability.sh"
    echo "  ./00_verify_requirements_traceability.sh <requirements_file> <source_file>"
    echo ""
    echo "Checks:"
    echo "  - Requirements IDs <-> source #R tags (strict)"
    echo "  - Requirement IDs -> discovered test #R tags (at least one per requirement)"
}

main() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        print_usage
        return 0
    fi
    if [ "$#" -eq 0 ]; then
        verify_all_requirements
        return $?
    fi
    if [ "$#" -eq 2 ]; then
        verify_single_pair_with_tests "$1" "$2"
        return $?
    fi
    print_usage
    return 1
}

main "$@"
