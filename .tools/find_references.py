#!/usr/bin/env python3
import os
import re
import sys

def find_references(pattern, directory='.'):
    """Find all references to a pattern in Python files."""
    pattern_re = re.compile(pattern)
    
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.py'):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r') as f:
                        content = f.read()
                    
                    line_num = 1
                    for line in content.splitlines():
                        if pattern_re.search(line):
                            print(f"{file_path}:{line_num}: {line.strip()}")
                        line_num += 1
                except Exception as e:
                    print(f"Error reading {file_path}: {e}", file=sys.stderr)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python find_references.py <pattern> [directory]")
        sys.exit(1)
    
    pattern = sys.argv[1]
    directory = sys.argv[2] if len(sys.argv) > 2 else '.'
    find_references(pattern, directory) 