#!/bin/bash
umask 007
set -euo pipefail

REQUIREMENTS_FILE="${1:-A_install_prerequisites-requirements.md}"
SCRIPT_FILE="${2:-01A_install_prerequisites.sh}"
REQ_IDS_FILE="$(mktemp)"
SCRIPT_IDS_FILE="$(mktemp)"
MISSING_IDS_FILE="$(mktemp)"
EXTRA_IDS_FILE="$(mktemp)"

if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "❌ Requirements file not found: $REQUIREMENTS_FILE"
    exit 1
fi

if [ ! -f "$SCRIPT_FILE" ]; then
    echo "❌ Script file not found: $SCRIPT_FILE"
    exit 1
fi

awk '
match($0, /^R[0-9]{3}(-[0-9]{3})?/) {
    print substr($0, RSTART, RLENGTH)
}
' "$REQUIREMENTS_FILE" | sort -u > "$REQ_IDS_FILE"

awk '
{
    while (match($0, /#R[0-9]{3}(-[0-9]{3})?/)) {
        id = substr($0, RSTART + 1, RLENGTH - 1)
        print id
        $0 = substr($0, RSTART + RLENGTH)
    }
}
' "$SCRIPT_FILE" | sort -u > "$SCRIPT_IDS_FILE"

comm -23 "$REQ_IDS_FILE" "$SCRIPT_IDS_FILE" > "$MISSING_IDS_FILE"
comm -13 "$REQ_IDS_FILE" "$SCRIPT_IDS_FILE" > "$EXTRA_IDS_FILE"

echo "Traceability check"
echo "- requirements: $REQUIREMENTS_FILE"
echo "- script: $SCRIPT_FILE"
echo ""

if [ ! -s "$MISSING_IDS_FILE" ] && [ ! -s "$EXTRA_IDS_FILE" ]; then
    echo "✅ PASS: Every requirement ID has a matching #R tag, and no extra tags were found."
    exit 0
fi

if [ -s "$MISSING_IDS_FILE" ]; then
    echo "❌ Missing #R tags for requirement IDs:"
    sed 's/^/  - /' "$MISSING_IDS_FILE"
fi

if [ -s "$EXTRA_IDS_FILE" ]; then
    echo "⚠️  Extra #R tags in script not present in requirements:"
    sed 's/^/  - /' "$EXTRA_IDS_FILE"
fi

exit 1
