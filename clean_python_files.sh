#!/bin/bash

set -e

TRASH_DIR="$HOME/.Trash"
if [ ! -d "$TRASH_DIR" ]; then
    TRASH_DIR="$HOME/.local/share/Trash/files"
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <python-files>"
    exit 1
fi

files=()
for pattern in "$@"; do
    for file in "$pattern"; do
        if [ -f "$file" ] && [[ $file == *.py ]]; then
            files+=("$file")
        fi
    done
done

if [ ${#files[@]} -eq 0 ]; then
    echo "No Python files found"
    exit 1
fi

echo "Found ${#files[@]} Python files to process"

echo "Phase 1: Cleaning files..."
for file in "${files[@]}"; do
    echo "Cleaning $file"
    if ! ./_clean_python_file.sh "$file" > "$file.cleaned"; then
        echo "Error cleaning $file"
        exit 1
    fi
    if [ ! -s "$file.cleaned" ]; then
        echo "Error: $file.cleaned is empty"
        rm "$file.cleaned"
        exit 1
    fi
done

echo "Phase 2: Copying permissions..."
for file in "${files[@]}"; do
    if [[ "$OSTYPE" == "darwin"* ]]; then
        PERMS=$(stat -f "%Lp" "$file")
    else
        PERMS=$(stat -c "%a" "$file")
    fi
    echo "Copying $PERMS permissions for $file"
    if ! chmod "$PERMS" "$file.cleaned"; then
        echo "Error copying permissions for $file"
        exit 1
    fi
done

echo "Phase 3: Moving originals to trash..."
for file in "${files[@]}"; do
    if [ ! -f "$file.cleaned" ]; then
        echo "Error: cleaned file missing for $file"
        exit 1
    fi
    echo "Moving $file to trash"
    if ! mv "$file" "$TRASH_DIR/"; then
        echo "Error moving $file to trash"
        exit 1
    fi
done

echo "Phase 4: Renaming cleaned files..."
for file in "${files[@]}"; do
    echo "Renaming $file.cleaned to $file"
    if ! mv "$file.cleaned" "$file"; then
        echo "Error renaming $file.cleaned"
        exit 1
    fi
done

echo "All operations completed successfully" 