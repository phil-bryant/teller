#!/bin/bash

awk '
    NR == 1 && /^#!/ { print; next }
    NF {
        if ($0 ~ /^[[:space:]]*@/) { decorator=1; print; next }
        if ($0 ~ /^[[:space:]]*class/) printf "\n"
        else if ($0 ~ /^[[:space:]]*(async[[:space:]]+)?def/ && p !~ /^[[:space:]]*class/) {
            if (!decorator) printf "\n"
            decorator=0
        }
        print
        p=$0
    }
' "$1" |
awk '
    NR == 1 { print; next }
    !/^[[:space:]]*#/ { print }
'