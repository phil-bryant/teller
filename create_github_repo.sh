#!/bin/bash

if [ "$#" -ne 1 ] || { [ "$1" != "--private" ] && [ "$1" != "--public" ]; }; then
    echo "Usage: $0 --private|--public"
    exit 1
fi

REPO_NAME=$(basename "$PWD")
VISIBILITY=${1#--}

if [ ! -d .git ]; then
    git init
    git add .
    git commit -m "Initial commit"
fi

gh repo create "$REPO_NAME" --"$VISIBILITY" --source=. --remote=origin --push

echo "Repository $REPO_NAME created and initialized with current directory contents"