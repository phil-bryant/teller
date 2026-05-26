#!/bin/bash
#R001: Use strict mode and temp files for deterministic comparisons.
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
    REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "$REPO_ROOT"

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

extract_scoped_source_ids() {
    local source_file="$1" out_file="$2"
    awk '{
        while (match($0, /#R[0-9]{3}(-[0-9]{3})*:[[:space:]]*[[:alnum:]_]/)) {
            token = substr($0, RSTART, RLENGTH)
            sub(/^#/, "", token)
            sub(/:.*/, "", token)
            print token
            $0 = substr($0, RSTART + RLENGTH)
        }
    }' "$source_file" | sort -u > "$out_file"
}

detect_header_bundle_tags() {
    local source_file="$1"
    awk '
        NR <= 40 {
            total = 0
            scoped = 0
            line = $0
            while (match(line, /#R[0-9]{3}(-[0-9]{3})*/)) {
                total += 1
                line = substr(line, RSTART + RLENGTH)
            }
            line_scoped = $0
            while (match(line_scoped, /#R[0-9]{3}(-[0-9]{3})*:/)) {
                scoped += 1
                line_scoped = substr(line_scoped, RSTART + RLENGTH)
            }
            if (total >= 3 && scoped == 0) {
                print NR ":" $0
                found = 1
                exit 0
            }
        }
        END { exit found ? 0 : 1 }
    ' "$source_file"
}

verify_scoped_traceability_comments() {
    local requirements_file="$1" source_file="$2"
    local req_ids_file scoped_ids_file missing_scoped_ids_file
    req_ids_file="$(mktemp)"
    scoped_ids_file="$(mktemp)"
    missing_scoped_ids_file="$(mktemp)"
    extract_requirement_ids "$requirements_file" "$req_ids_file"
    extract_scoped_source_ids "$source_file" "$scoped_ids_file"
    comm -23 "$req_ids_file" "$scoped_ids_file" > "$missing_scoped_ids_file"
    if [ ! -s "$missing_scoped_ids_file" ]; then
        return 0
    fi
    echo "❌ Missing scoped #R comments (#Rxxx:) for requirement IDs:"
    sed 's/^/  - /' "$missing_scoped_ids_file"
    return 1
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
                if (token ~ /^[A-Za-z0-9._\/-]+\.(sh|py|swift|sql|c|cc|cpp|cxx|m|mm|h|hpp)$/ || token == "Makefile" || token == ".gitignore") {
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
allowed_exts = {"sh", "py", "swift", "sql", "c", "cc", "cpp", "cxx", "m", "mm", "h", "hpp"}
allowed_stems = {"Makefile", ".gitignore"}
matches = []

if os.path.isdir(search_root):
    for root, _dirs, files in os.walk(search_root):
        for name in files:
            base, dot, ext = name.rpartition(".")
            if not dot:
                continue
            if base == stem and ext in allowed_exts:
                matches.append(os.path.join(root, name))
            if name == stem and name in allowed_stems:
                matches.append(os.path.join(root, name))

for path in sorted(set(matches)):
    print(path)
PY
}

extract_ui_required_ids()
{   local requirements_file="$1" out_file="$2"
    awk '{  line = tolower($0)
            if (match(line, /^r[0-9]{3}(-[0-9]{3})*[[:space:]]+statement:/))
            {   rid = toupper($1)
                if (line ~ /ui[[:space:]-]*test/ || line ~ /xcuitest/ || line ~ /xctest[[:space:]-]*ui/ || line ~ /ui[[:space:]-]*mode/)
                {   print rid
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
    normalized_requirements = os.path.realpath(requirements_file)
    marker = f"{os.sep}requirements{os.sep}"
    if marker in normalized_requirements:
        inferred_root = normalized_requirements.split(marker, 1)[0]
        if inferred_root and os.path.isdir(inferred_root):
            repo_root = inferred_root
    try:
        requirements_file = os.path.relpath(normalized_requirements, repo_root)
    except ValueError:
        requirements_file = normalized_requirements

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

requirements_base = os.path.basename(requirements_file)
requirements_stem = requirements_base
if requirements_stem.endswith("-requirements.md"):
    requirements_stem = requirements_stem[:-len("-requirements.md")]
add_path(f"tests/sh/{requirements_stem}.bats", "default")

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
    if base == "Makefile":
        add_path("tests/sh/Makefile.bats", "default")
    if ext == ".py":
        if source_norm.startswith("src/teller/"):
            add_path(f"tests/py/test_{stem}.py", "default")
        elif source_norm.startswith(tuple(f"{n:02d}_" for n in range(100))):
            add_path(f"tests/sh/{stem}.bats", "default")
        else:
            add_path(f"tests/py/test_{stem}.py", "default")
    if ext == ".sql":
        add_path(f"tests/sh/{stem}.bats", "default")
        add_path(f"tests/sql/{stem}.sql", "default")
        add_path(f"tests/sql/test_{stem}.sql", "default")
    if ext == ".swift" and source_norm.startswith("src/macos-ui/Sources/"):
        collect_swift_lane("src/macos-ui/Tests", "default", stem=stem)
        collect_swift_lane("src/macos-ui/UITests", "ui", stem=stem)

if requirements_file.startswith("requirements/macos-ui/"):
    collect_swift_lane("src/macos-ui/UITests", "ui")

# R020/R035 in 05 are marked as UI (XCUITest) in the requirements text; include UI lane.
if os.path.basename(requirements_file) == "16_run_macos_ui_regression_tests-requirements.md":
    collect_swift_lane("src/macos-ui/UITests", "ui")

with open(default_tests_file, "w", encoding="utf-8") as handle:
    for item in sorted(default_results):
        handle.write(f"{item}\n")

with open(ui_tests_file, "w", encoding="utf-8") as handle:
    for item in sorted(ui_results):
        handle.write(f"{item}\n")
PY
}

tests_inline_from_list() {
    local test_list_file="$1"
    python3 - "$test_list_file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print("(none discovered)")
    raise SystemExit(0)

items = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
if not items:
    print("(none discovered)")
else:
    print(", ".join(items))
PY
}

discover_combined_tests_for_requirements() {
    local requirements_file="$1" source_list_file="$2" combined_tests_file="$3"
    local default_tests_file ui_tests_file
    default_tests_file="$(mktemp)"
    ui_tests_file="$(mktemp)"
    discover_test_files_for_requirements "$requirements_file" "$source_list_file" "$default_tests_file" "$ui_tests_file"
    cat "$default_tests_file" "$ui_tests_file" | sort -u > "$combined_tests_file"
}

extract_numbered_test_ids() {
    local test_file="$1" out_file="$2" misplaced_file="$3"
    python3 - "$test_file" "$out_file" "$misplaced_file" <<'PY'
import re
import sys
from pathlib import Path

test_file = Path(sys.argv[1])
out_file = Path(sys.argv[2])
misplaced_file = Path(sys.argv[3])

tag_re = re.compile(r"#(R\d{3}(?:-\d{3})*-T\d{2})")
bats_start_re = re.compile(
    r'^\s*(?:@test\b.*\{\s*$|bats_test_function\b.*\{\s*$|[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{\s*$)'
)
python_start_re = re.compile(r'^\s*def\s+test[_A-Za-z0-9]*\s*\(')
swift_start_re = re.compile(r'^\s*func\s+test[_A-Za-z0-9]*\s*\(')

suffix = test_file.suffix.lower()
is_bats = suffix == ".bats"
is_python = suffix == ".py"
is_swift = suffix == ".swift"
enforce_scoped = is_bats or is_python or is_swift

ids = set()
misplaced = []

if not test_file.exists():
    out_file.write_text("", encoding="utf-8")
    misplaced_file.write_text("", encoding="utf-8")
    raise SystemExit(0)

lines = test_file.read_text(encoding="utf-8").splitlines()

if not enforce_scoped:
    for line in lines:
        for match in tag_re.finditer(line):
            ids.add(match.group(1))
else:
    in_test_block = False
    brace_depth = 0
    block_indent = 0
    idx = 0
    while idx < len(lines):
        line_number = idx + 1
        line = lines[idx]
        line_tags = [match.group(1) for match in tag_re.finditer(line)]
        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" \t"))
        if is_python:
            while True:
                if not in_test_block and python_start_re.search(line):
                    in_test_block = True
                    block_indent = indent
                    for tag in line_tags:
                        ids.add(tag)
                    break
                if in_test_block:
                    # A dedent starts a new statement outside the active test function.
                    if stripped and indent <= block_indent and not python_start_re.search(line):
                        in_test_block = False
                        continue
                    for tag in line_tags:
                        ids.add(tag)
                    break
                for tag in line_tags:
                    misplaced.append(f"{test_file}:{line_number}: #{tag}")
                break
        elif is_bats:
            if not in_test_block and bats_start_re.search(line):
                in_test_block = True
            if in_test_block:
                for tag in line_tags:
                    ids.add(tag)
                brace_depth += line.count("{")
                brace_depth -= line.count("}")
                if brace_depth <= 0:
                    in_test_block = False
                    brace_depth = 0
            else:
                for tag in line_tags:
                    misplaced.append(f"{test_file}:{line_number}: #{tag}")
        elif is_swift:
            if not in_test_block and swift_start_re.search(line):
                in_test_block = True
            if in_test_block:
                for tag in line_tags:
                    ids.add(tag)
                brace_depth += line.count("{")
                brace_depth -= line.count("}")
                if brace_depth <= 0:
                    in_test_block = False
                    brace_depth = 0
            else:
                for tag in line_tags:
                    misplaced.append(f"{test_file}:{line_number}: #{tag}")
        idx += 1

out_file.write_text("".join(f"{item}\n" for item in sorted(ids)), encoding="utf-8")
misplaced_file.write_text("".join(f"{item}\n" for item in misplaced), encoding="utf-8")
PY
}

collect_numbered_test_ids_from_list() {
    local test_list_file="$1" out_file="$2"
    local test_file tmp_ids misplaced_tags_file one_file_misplaced
    tmp_ids="$(mktemp)"
    misplaced_tags_file="$(mktemp)"
    : > "$tmp_ids"
    : > "$misplaced_tags_file"
    if [ ! -s "$test_list_file" ]; then
        : > "$out_file"
        return 0
    fi
    while IFS= read -r test_file; do
        [ -n "$test_file" ] || continue
        [ -f "$test_file" ] || continue
        local one_file_ids
        one_file_ids="$(mktemp)"
        one_file_misplaced="$(mktemp)"
        extract_numbered_test_ids "$test_file" "$one_file_ids" "$one_file_misplaced"
        cat "$one_file_ids" >> "$tmp_ids"
        cat "$one_file_misplaced" >> "$misplaced_tags_file"
    done < "$test_list_file"
    sort -u "$tmp_ids" > "$out_file"
    sort -u "$misplaced_tags_file" -o "$misplaced_tags_file"
    if [ -s "$misplaced_tags_file" ]; then
        echo "❌ FAIL (numbered-test-tag-placement): numbered #Rxxx-T## tags must be inside executable test blocks:"
        sed 's/^/  - /' "$misplaced_tags_file"
        echo "  - Move numbered tags into @test/def test*/func test* bodies."
        return 1
    fi
}

extract_numbered_requirement_test_ids() {
    local requirements_file="$1" out_file="$2"
    python3 - "$requirements_file" "$out_file" <<'PY'
import re
import sys
from pathlib import Path

requirements_file = Path(sys.argv[1])
out_file = Path(sys.argv[2])

req_line_re = re.compile(r'^(R\d{3}(?:-\d{3})*)\s+Statement:')
numbered_test_re = re.compile(r'^-\s+(R\d{3}(?:-\d{3})*)-T(\d{2})\s*:')

current_requirement_id = None
in_tests = False
ids = set()

for raw_line in requirements_file.read_text(encoding="utf-8").splitlines():
    stripped = raw_line.strip()
    req_match = req_line_re.match(stripped)
    if req_match:
        current_requirement_id = req_match.group(1)
        in_tests = False
        continue
    if stripped == "Tests:":
        in_tests = True
        continue
    if in_tests and stripped.startswith("- "):
        match = numbered_test_re.match(stripped)
        if match and current_requirement_id and match.group(1) == current_requirement_id:
            ids.add(f"{match.group(1)}-T{match.group(2)}")
        continue
    if in_tests and stripped and not stripped.startswith("- "):
        in_tests = False

with out_file.open("w", encoding="utf-8") as handle:
    for item in sorted(ids):
        handle.write(f"{item}\n")
PY
}

verify_requirements_numbered_test_bullets() {
    local requirements_file="$1"
    python3 - "$requirements_file" <<'PY'
import re
import sys
from pathlib import Path

requirements_file = Path(sys.argv[1])
lines = requirements_file.read_text(encoding="utf-8").splitlines()

req_line_re = re.compile(r'^(R\d{3}(?:-\d{3})*)\s+Statement:')
numbered_test_re = re.compile(r'^-\s+(R\d{3}(?:-\d{3})*)-T(\d{2})\s*:')

current_requirement_id = None
in_tests = False
seen_numbers = {}
issues = []

for idx, raw_line in enumerate(lines, start=1):
    stripped = raw_line.strip()
    req_match = req_line_re.match(stripped)
    if req_match:
        current_requirement_id = req_match.group(1)
        in_tests = False
        seen_numbers.setdefault(current_requirement_id, [])
        continue
    if stripped == "Tests:":
        in_tests = True
        continue
    if in_tests and stripped.startswith("- "):
        match = numbered_test_re.match(stripped)
        if not match:
            expected = ""
            if current_requirement_id:
                next_number = len(seen_numbers.get(current_requirement_id, [])) + 1
                expected = f" (expected prefix: {current_requirement_id}-T{next_number:02d})"
            issues.append(f"{requirements_file}:{idx}: unnumbered/invalid test bullet under Tests:{expected}")
            continue
        bullet_requirement_id = match.group(1)
        bullet_test_number = int(match.group(2))
        if current_requirement_id and bullet_requirement_id != current_requirement_id:
            issues.append(
                f"{requirements_file}:{idx}: test bullet {bullet_requirement_id}-T{bullet_test_number:02d} does not match requirement {current_requirement_id}"
            )
            continue
        if current_requirement_id:
            seen_numbers[current_requirement_id].append(bullet_test_number)
        continue
    if in_tests and stripped and not stripped.startswith("- "):
        in_tests = False

if issues:
    for issue in issues:
        print(issue)
    raise SystemExit(1)
PY
}

#R090: Enforce numbered test tags (#Rxxx-T##) in discovered test files for each requirement ID.
verify_numbered_test_traceability() {
    local requirements_file="$1" source_list_file="$2"
    if [ "${STRICT_TRACEABILITY_NUMBERED_TAGS:-true}" = "false" ]; then
        echo "ℹ️  Numbered test-tag enforcement skipped for ${requirements_file} (set STRICT_TRACEABILITY_NUMBERED_TAGS=true to re-enable)."
        return 0
    fi
    local req_ids_file req_numbered_test_ids_file combined_tests_file numbered_test_ids_file scoped_test_ids_file missing_file extra_file missing_req_testcase_ids_file
    req_ids_file="$(mktemp)"
    req_numbered_test_ids_file="$(mktemp)"
    combined_tests_file="$(mktemp)"
    numbered_test_ids_file="$(mktemp)"
    scoped_test_ids_file="$(mktemp)"
    missing_file="$(mktemp)"
    extra_file="$(mktemp)"
    missing_req_testcase_ids_file="$(mktemp)"
    extract_requirement_ids "$requirements_file" "$req_ids_file"
    extract_numbered_requirement_test_ids "$requirements_file" "$req_numbered_test_ids_file"
    discover_combined_tests_for_requirements "$requirements_file" "$source_list_file" "$combined_tests_file"
    if ! collect_numbered_test_ids_from_list "$combined_tests_file" "$numbered_test_ids_file"; then
        return 1
    fi
    : > "$missing_req_testcase_ids_file"
    while IFS= read -r req_id; do
        [ -n "$req_id" ] || continue
        if awk -v id="$req_id" 'index($0, id "-T") == 1 { found=1 } END { exit found ? 0 : 1 }' "$req_numbered_test_ids_file"; then
            continue
        fi
        printf "%s\n" "$req_id" >> "$missing_req_testcase_ids_file"
    done < "$req_ids_file"
    sort -u "$missing_req_testcase_ids_file" -o "$missing_req_testcase_ids_file"
    if [ -s "$missing_req_testcase_ids_file" ]; then
        echo "❌ FAIL (numbered-test-tags): missing Rxxx-T## entries in ${requirements_file} for requirement IDs:"
        sed 's/^/  - /' "$missing_req_testcase_ids_file"
        return 1
    fi

    awk '
        NR == FNR { req[$1] = 1; next }
        {
            split($0, parts, "-T")
            req_id = parts[1]
            if (req_id in req) {
                print $0
            }
        }
    ' "$req_ids_file" "$numbered_test_ids_file" | sort -u > "$scoped_test_ids_file"
    comm -23 "$req_numbered_test_ids_file" "$scoped_test_ids_file" > "$missing_file"
    comm -13 "$req_numbered_test_ids_file" "$scoped_test_ids_file" > "$extra_file"
    if [ ! -s "$missing_file" ] && [ ! -s "$extra_file" ]; then
        echo "✅ PASS (numbered-test-tags): ${requirements_file}"
        return 0
    fi
    echo "❌ FAIL (numbered-test-tags): requirements/tests #Rxxx-T## are not 1:1 for ${requirements_file}:"
    if [ -s "$missing_file" ]; then
        echo "  Missing in tests (present in requirements):"
        sed 's/^/    - /' "$missing_file"
    fi
    if [ -s "$extra_file" ]; then
        echo "  Missing in requirements (present in tests):"
        sed 's/^/    - /' "$extra_file"
    fi
    return 1
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
    local req_ids_file ui_req_ids_file default_tests_file ui_tests_file combined_tests_file tests_inline
    local default_test_ids_file ui_test_ids_file missing_test_ids_file
    req_ids_file="$(mktemp)"
    ui_req_ids_file="$(mktemp)"
    default_tests_file="$(mktemp)"
    ui_tests_file="$(mktemp)"
    default_test_ids_file="$(mktemp)"
    ui_test_ids_file="$(mktemp)"
    missing_test_ids_file="$(mktemp)"
    combined_tests_file="$(mktemp)"
    #R050: Discover test files by requirements/source conventions and test lanes.
    discover_test_files_for_requirements "$requirements_file" "$source_list_file" "$default_tests_file" "$ui_tests_file"
    cat "$default_tests_file" "$ui_tests_file" | sort -u > "$combined_tests_file"
    tests_inline="$(tests_inline_from_list "$combined_tests_file")"
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
        echo "✅ PASS (test-traceability): ${requirements_file} -> ${tests_inline}"
        return 0
    fi
    echo "❌ FAIL (test-traceability): missing tagged tests for requirement IDs in ${requirements_file}:"
    sed 's/^/  - /' "$missing_test_ids_file"
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

is_requirements_only_mode() {
    local requirements_file="$1"
    awk '
        /^## Scope$/ { in_scope = 1; next }
        /^## / && in_scope { in_scope = 0 }
        /^R[0-9]{3}(-[0-9]{3})*/ && in_scope { in_scope = 0 }
        in_scope {
            line = tolower($0)
            if (line ~ /^[[:space:]]*requirements-only mode:[[:space:]]*true[[:space:]]*\.?[[:space:]]*$/) {
                found = 1
            }
        }
        END { exit found ? 0 : 1 }
    ' "$requirements_file"
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
    local print_banner="${3:-1}"
    if [ "$print_banner" -eq 1 ]; then
        echo ""
        echo "Traceability check"
        echo "- requirements: $requirements_file"
        echo "- source: $source_file"
    fi
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
    local header_bundle_line
    header_bundle_line="$(detect_header_bundle_tags "$source_file" || true)"
    if [ -n "$header_bundle_line" ]; then
        #R070: Reject header-level bundled tags as anti-cheat pattern.
        echo "❌ FAIL (anti-cheat): header-level bundled #R tags detected in ${source_file}:"
        echo "  - ${header_bundle_line}"
        echo "  - Use scoped comments like '#R020: behavior' above each implementation block."
        return 1
    fi
    if ! verify_strict_pair "$requirements_file" "$source_file"; then
        return 1
    fi
    #R070: Require scoped traceability comments (#Rxxx:) in source blocks.
    verify_scoped_traceability_comments "$requirements_file" "$source_file"
}

verify_single_pair_with_tests() {
    local requirements_file="$1" source_file="$2"
    local source_list_file combined_tests_file tests_inline status=0
    if is_requirements_only_mode "$requirements_file"; then
        #R075: Skip source/test traceability for explicit requirements-only docs.
        echo "✅ PASS (requirements-only): ${requirements_file} (source/test traceability skipped)"
        return 0
    fi
    source_list_file="$(mktemp)"
    combined_tests_file="$(mktemp)"
    printf "%s\n" "$source_file" > "$source_list_file"
    discover_combined_tests_for_requirements "$requirements_file" "$source_list_file" "$combined_tests_file"
    tests_inline="$(tests_inline_from_list "$combined_tests_file")"
    echo ""
    echo "Traceability check"
    echo "- requirements: $requirements_file"
    echo "- source: $source_file"
    echo "- tests: $tests_inline"
    if is_locked_source_file "$source_file"; then
        # Locked sources use policy-based verification and are excluded from automatic test-tag pairing.
        verify_single_pair "$requirements_file" "$source_file" 0
        return $?
    fi
    if ! verify_single_pair "$requirements_file" "$source_file" 0; then
        status=1
    fi
    if ! verify_requirements_test_traceability "$requirements_file" "$source_list_file"; then
        status=1
    fi
    if ! verify_requirements_numbered_test_bullets "$requirements_file"; then
        echo "❌ FAIL (requirements-numbered-tests): ${requirements_file} contains malformed test bullets."
        status=1
    fi
    #R090: Enforce numbered test tags for each requirement ID.
    if ! verify_numbered_test_traceability "$requirements_file" "$source_list_file"; then
        status=1
    fi
    [ "$status" -eq 0 ]
}

verify_requirements_file_sources() {
    local requirements_file="$1"
    local source_list_file source_file found_source=0 file_fail=0 enforceable_source_list_file
    if is_requirements_only_mode "$requirements_file"; then
        #R075: Skip source/test traceability for explicit requirements-only docs.
        echo "✅ PASS (requirements-only): ${requirements_file} (source/test traceability skipped)"
        return 0
    fi
    source_list_file="$(mktemp)"
    enforceable_source_list_file="$(mktemp)"
    : > "$enforceable_source_list_file"
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
        if ! is_locked_source_file "$source_file"; then
            printf "%s\n" "$source_file" >> "$enforceable_source_list_file"
        fi
        local one_source_file one_source_tests_file one_source_tests_inline
        one_source_file="$(mktemp)"
        one_source_tests_file="$(mktemp)"
        printf "%s\n" "$source_file" > "$one_source_file"
        discover_combined_tests_for_requirements "$requirements_file" "$one_source_file" "$one_source_tests_file"
        one_source_tests_inline="$(tests_inline_from_list "$one_source_tests_file")"
        echo ""
        echo "Traceability check"
        echo "- requirements: $requirements_file"
        echo "- source: $source_file"
        echo "- tests: $one_source_tests_inline"
        if verify_single_pair "$requirements_file" "$source_file" 0; then
            echo "✅ PASS: ${requirements_file} -> ${source_file}"
        else
            echo "❌ FAIL: ${requirements_file} -> ${source_file}"
            file_fail=1
        fi
    done < "$source_list_file"
    if [ -s "$enforceable_source_list_file" ]; then
        if ! verify_requirements_test_traceability "$requirements_file" "$enforceable_source_list_file"; then
            file_fail=1
        fi
        if ! verify_requirements_numbered_test_bullets "$requirements_file"; then
            echo "❌ FAIL (requirements-numbered-tests): ${requirements_file} contains malformed test bullets."
            file_fail=1
        fi
        #R090: Enforce numbered test tags for each requirement ID.
        if ! verify_numbered_test_traceability "$requirements_file" "$enforceable_source_list_file"; then
            file_fail=1
        fi
    else
        echo "✅ PASS (locked-source-test-skip): ${requirements_file} (all mapped sources are policy-locked)"
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
    echo ""
    #R040: Enforce numbered-script-to-numbered-requirements coverage completeness.
    verify_numbered_script_requirements_coverage || fail=$((fail + 1))
    #R045: Enforce numbered requirements docs map to same-numbered numbered scripts.
    verify_numbered_requirement_scope_alignment || fail=$((fail + 1))
    #R080: Enforce numbered script-to-test coverage completeness for Teller stack scripts.
    verify_numbered_script_test_coverage || fail=$((fail + 1))
    #R085: Enforce repository software-to-requirements coverage completeness.
    verify_repository_source_requirements_coverage || fail=$((fail + 1))
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
    for script_file in tests/[0-9][0-9]_*.sh tests/[0-9][0-9]_*.py [0-9][0-9]_*.sh [0-9][0-9]_*.py; do
        [ -e "$script_file" ] || continue
        num="$(basename "${script_file%%_*}")"
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
                tests/[0-9][0-9]_*.sh|tests/[0-9][0-9]_*.py|[0-9][0-9]_*.sh|[0-9][0-9]_*.py)
                    found_numbered_source="true"
                    source_file_base="$(basename "$source_file")"
                    if [ "${source_file_base%%_*}" = "$req_num" ]; then
                        matched_numbered_source="true"
                    fi
                    ;;
                tests/t[0-9][0-9]_*.sh|tests/t[0-9][0-9]_*.py)
                    # tNN_* lane scripts are intentionally decoupled from requirements NN prefix.
                    found_numbered_source="true"
                    matched_numbered_source="true"
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

verify_numbered_script_test_coverage() {
    if [ "${STRICT_TRACEABILITY_FULL_COVERAGE:-true}" = "false" ]; then
        echo "ℹ️  Numbered script test-coverage check skipped (set STRICT_TRACEABILITY_FULL_COVERAGE=true to re-enable)."
        return 0
    fi
    local script_file stem missing
    missing="false"
    for script_file in tests/[0-9][0-9]_*.sh tests/[0-9][0-9]_*.py [0-9][0-9]_*.sh [0-9][0-9]_*.py; do
        [ -e "$script_file" ] || continue
        stem="$(basename "${script_file%.*}")"
        if [ -f "tests/sh/${stem}.bats" ]; then
            continue
        fi
        if [ "$missing" = "false" ]; then
            echo "❌ FAIL: numbered scripts missing companion shell tests:"
        fi
        echo "  - ${script_file} (expected tests/sh/${stem}.bats)"
        missing="true"
    done
    if [ "$missing" = "false" ]; then
        echo "✅ PASS: numbered script test coverage complete (every numbered script has tests/sh/NN_*.bats)."
        return 0
    fi
    return 1
}

list_repository_software_files() {
    local out_file="$1" excluded_path="${2:-}"
    python3 - "$out_file" "$excluded_path" <<'PY'
import os
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
excluded_path = sys.argv[2].strip()
repo_root = Path.cwd().resolve()
excluded_real = ""
if excluded_path:
    excluded_real = str(Path(excluded_path).resolve())
allowed_exts = {".sh", ".py", ".swift", ".sql", ".c", ".cc", ".cpp", ".cxx", ".m", ".mm", ".h", ".hpp"}
excluded_dirs = {
    ".git",
    ".cursor",
    "requirements",
    "tests",
    "Tests",
    "bin",
    "backups",
    "artifacts",
    ".gocache",
    ".gomodcache",
    ".build",
    "__pycache__",
    ".venv",
    "venv",
    "site-packages",
    ".mypy_cache",
    ".tox",
    "node_modules",
    ".gradle",
    "Pods",
    ".swiftpm",
    "teller-venv",
    ".derivedData-ui-tests",
}
excluded_dir_prefixes = (".derivedData",)
excluded_relative_paths = {"storage/schema.sql"}
excluded_relative_prefixes = (
    "storage/sql/",
    "archive/",
    "src/macos-ui/",
    "src/sql/postgres/",
    "src/teller/",
)
files = set()
for root, dirs, filenames in os.walk(repo_root):
    dirs[:] = [
        d for d in dirs
        if d not in excluded_dirs and not any(d.startswith(prefix) for prefix in excluded_dir_prefixes)
    ]
    for filename in filenames:
        path = Path(root) / filename
        if excluded_real and str(path.resolve()) == excluded_real:
            continue
        if path.suffix.lower() in allowed_exts:
            rel = path.relative_to(repo_root).as_posix()
            if rel in excluded_relative_paths:
                continue
            if any(rel.startswith(prefix) for prefix in excluded_relative_prefixes):
                continue
            files.add(rel)
with out_path.open("w", encoding="utf-8") as handle:
    for rel in sorted(files):
        handle.write(f"{rel}\n")
PY
}

verify_repository_source_requirements_coverage() {
    if [ "${STRICT_TRACEABILITY_FULL_COVERAGE:-true}" = "false" ]; then
        echo "ℹ️  Repository software coverage check skipped (set STRICT_TRACEABILITY_FULL_COVERAGE=true to re-enable)."
        return 0
    fi
    local all_sources_file covered_sources_file uncovered_sources_file req_file source_file
    all_sources_file="$(mktemp)"
    covered_sources_file="$(mktemp)"
    uncovered_sources_file="$(mktemp)"
    #R085: Auto-detect repository software files missing requirements coverage.
    list_repository_software_files "$all_sources_file" "$0"
    : > "$covered_sources_file"
    while IFS= read -r req_file; do
        [ -n "$req_file" ] || continue
        local source_list_file
        source_list_file="$(mktemp)"
        if is_requirements_only_mode "$req_file"; then
            continue
        fi
        extract_source_files_from_requirements "$req_file" "$source_list_file"
        if [ ! -s "$source_list_file" ]; then
            extract_source_files_from_analogous_tree "$req_file" "$source_list_file"
        fi
        while IFS= read -r source_file; do
            [ -n "$source_file" ] || continue
            if [ -f "$source_file" ]; then
                printf "%s\n" "$source_file" >> "$covered_sources_file"
            fi
        done < "$source_list_file"
    done < <(list_requirements_files)
    sort -u "$covered_sources_file" -o "$covered_sources_file"
    comm -23 "$all_sources_file" "$covered_sources_file" > "$uncovered_sources_file"
    if [ ! -s "$uncovered_sources_file" ]; then
        echo "✅ PASS: repository software files are covered by requirements docs."
        return 0
    fi
    echo "❌ FAIL: repository software files missing requirements coverage:"
    sed 's/^/  - /' "$uncovered_sources_file"
    return 1
}

print_usage() {
    echo "Usage:"
    echo "  ./tests/t04_run_requirements_traceability_tests.sh"
    echo "  ./tests/t04_run_requirements_traceability_tests.sh <requirements_file> <source_file>"
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
