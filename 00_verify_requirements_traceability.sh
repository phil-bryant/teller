#!/bin/bash
#R001: Use strict mode and temp files for deterministic comparisons.
umask 007
set -euo pipefail

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

verify_requirements_file_sources() {
    local requirements_file="$1"
    local source_list_file source_file found_source=0 file_fail=0
    source_list_file="$(mktemp)"
    #R010: Resolve source files referenced by each requirements document.
    extract_source_files_from_requirements "$requirements_file" "$source_list_file"
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
    if [ "$found_source" -eq 0 ]; then
        echo "❌ FAIL: ${requirements_file} has no source files to verify."
        return 1
    fi
    [ "$file_fail" -eq 0 ]
}

verify_all_requirements() {
    local total=0 pass=0 fail=0 requirements_file
    local requirements_files=(requirements/*.md)
    #R005: Discover and verify all requirements/*.md by default.
    if [ "${requirements_files[0]}" = "requirements/*.md" ]; then
        echo "❌ FAIL: no requirements files found under requirements/*.md"
        return 1
    fi
    echo "Traceability check for all requirements/*.md"
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
        verify_single_pair "$1" "$2"
        return $?
    fi
    print_usage
    return 1
}

main "$@"
