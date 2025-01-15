#!/bin/bash
set -e

# First batch - database and roles
psql -U postgres -f 00_create_database.sql
psql -U postgres -d prod -f 01_configure_database.sql

# Second batch - schema objects in dependency order
for i in {2..13}; do
    padded_num=$(printf "%02d" $i)
    file=$(ls ${padded_num}_*.sql 2>/dev/null || true)
    
    if [ -z "$file" ]; then
        echo "No file found starting with ${padded_num}_"
        continue
    fi
    
    echo "Running $file..."
    psql -U teller -d prod -f "$file"
done

echo "Deployment complete!" 