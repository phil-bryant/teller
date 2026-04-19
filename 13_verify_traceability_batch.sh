#!/bin/bash
umask 007
set -euo pipefail

PAIR_LIST="
02_create_venv-requirements.md|02_create_venv.sh|strict
03_load_requirements-requirements.md|03_load_requirements.sh|locked
04_deploy_database-requirements.md|04_deploy_database.sh|strict
05_configure_teller_io-requirements.md|05_configure_teller_io.sh|strict
06_capture_teller_token-requirements.md|06_capture_teller_token.sh|strict
07_teller_client-requirements.md|07_teller_client.py|strict
08_backfill_statements-requirements.md|08_backfill_statements.py|strict
09_transaction_reclassification_api-requirements.md|09_transaction_reclassification_api.py|strict
11_verify_reclassification_persistence-requirements.md|11_verify_reclassification_persistence.sh|strict
12_verify_prereq_traceability-requirements.md|12_verify_prereq_traceability.sh|strict
97_backup_database-requirements.md|97_backup_database.sh|strict
98_destroy_database-requirements.md|98_destroy_database.sh|strict
99_restore_database-requirements.md|99_restore_database.sh|strict
"

extract_requirement_ids() {
    local requirements_file="$1" out_file="$2"
    awk 'match($0, /^R[0-9]{3}(-[0-9]{3})?/) { print substr($0, RSTART, RLENGTH) }' "$requirements_file" | sort -u > "$out_file"
}

extract_script_ids() {
    local script_file="$1" out_file="$2"
    awk '{
        while (match($0, /#R[0-9]{3}(-[0-9]{3})?/)) {
            id = substr($0, RSTART + 1, RLENGTH - 1)
            print id
            $0 = substr($0, RSTART + RLENGTH)
        }
    }' "$script_file" | sort -u > "$out_file"
}

verify_locked_exception() {
    local requirements_file="$1" script_file="$2"
    local marker_a marker_b
    marker_a="$(awk '/<AI_MODEL_INSTRUCTION>/{ print "yes"; exit }' "$script_file")"
    marker_b="$(awk '/DO_NOT_MODIFY_THIS_FILE/{ print "yes"; exit }' "$script_file")"
    if [ "$marker_a" != "yes" ] || [ "$marker_b" != "yes" ]; then
        echo "❌ FAIL (locked-policy): ${script_file} is missing expected lock markers."
        return 1
    fi
    if ! awk 'match($0, /^R030[[:space:]]+Statement:/) { found=1 } END { exit found ? 0 : 1 }' "$requirements_file"; then
        echo "❌ FAIL (locked-policy): ${requirements_file} is missing R030 locked-traceability requirement."
        return 1
    fi
    echo "✅ PASS (locked-policy): ${script_file} verified-with-exception."
    return 0
}

verify_strict_pair() {
    local requirements_file="$1" script_file="$2"
    local req_ids_file script_ids_file missing_ids_file extra_ids_file
    req_ids_file="$(mktemp)"
    script_ids_file="$(mktemp)"
    missing_ids_file="$(mktemp)"
    extra_ids_file="$(mktemp)"
    extract_requirement_ids "$requirements_file" "$req_ids_file"
    extract_script_ids "$script_file" "$script_ids_file"
    comm -23 "$req_ids_file" "$script_ids_file" > "$missing_ids_file"
    comm -13 "$req_ids_file" "$script_ids_file" > "$extra_ids_file"
    if [ ! -s "$missing_ids_file" ] && [ ! -s "$extra_ids_file" ]; then
        echo "✅ PASS: ${script_file}"
        return 0
    fi
    echo "❌ FAIL: ${script_file}"
    if [ -s "$missing_ids_file" ]; then
        echo "  Missing #R tags:"
        sed 's/^/    - /' "$missing_ids_file"
    fi
    if [ -s "$extra_ids_file" ]; then
        echo "  Extra #R tags not in requirements:"
        sed 's/^/    - /' "$extra_ids_file"
    fi
    return 1
}

main() {
    local total=0 pass=0 fail=0 requirements_file script_file mode
    echo "Batch traceability check"
    while IFS='|' read -r requirements_file script_file mode; do
        [ -n "$requirements_file" ] || continue
        total=$((total + 1))
        if [ ! -f "$requirements_file" ]; then
            echo "❌ FAIL: missing requirements file ${requirements_file}"
            fail=$((fail + 1))
            continue
        fi
        if [ ! -f "$script_file" ]; then
            echo "❌ FAIL: missing script file ${script_file}"
            fail=$((fail + 1))
            continue
        fi
        if [ "$mode" = "locked" ]; then
            if verify_locked_exception "$requirements_file" "$script_file"; then pass=$((pass + 1)); else fail=$((fail + 1)); fi
            continue
        fi
        if verify_strict_pair "$requirements_file" "$script_file"; then pass=$((pass + 1)); else fail=$((fail + 1)); fi
    done <<EOF
$PAIR_LIST
EOF
    echo ""
    echo "Summary: total=${total} pass=${pass} fail=${fail}"
    if [ "$fail" -eq 0 ]; then
        echo "✅ All traceability checks passed."
        exit 0
    fi
    echo "❌ One or more traceability checks failed."
    exit 1
}

main "$@"
