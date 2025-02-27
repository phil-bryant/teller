#!/usr/bin/env python3
import os
import re
import sys

def update_file(filepath):
    """Update List to list and Dict to dict in a Python file."""
    with open(filepath, 'r') as file:
        content = file.read()
    
    original_content = content
    
    # A more thorough approach to handle imports
    typing_import_pattern = r'from typing import (.*?)$'
    
    def replace_typing_imports(match):
        imports = match.group(1)
        # Replace List with list and Dict with dict
        imports = re.sub(r'\bList\b', 'list', imports)
        imports = re.sub(r'\bDict\b', 'dict', imports)
        
        # Remove list and dict since they're built-in
        items = [item.strip() for item in imports.split(',')]
        filtered_items = [item for item in items if item not in ('list', 'dict')]
        
        if filtered_items:
            return f"from typing import {', '.join(filtered_items)}"
        else:
            return ""  # Empty import
    
    # Process multiline imports too
    content = re.sub(typing_import_pattern, replace_typing_imports, content, flags=re.MULTILINE)
    
    # Replace type annotations
    content = re.sub(r'List\[', r'list[', content)
    content = re.sub(r'Dict\[', r'dict[', content)
    
    # Clean up any empty lines created
    content = re.sub(r'\n\s*\n\s*\n', '\n\n', content)
    
    # Only write if changes were made
    if content != original_content:
        with open(filepath, 'w') as file:
            file.write(content)
        return True
    return False

def scan_directory(directory='.'):
    """Recursively scan directory for Python files and update them."""
    updated_files = []
    skipped_files = []
    
    for root, _, files in os.walk(directory):
        # Skip virtual environment and version control directories
        if (('/teller-venv/' in root) or 
            ('/.git/' in root) or 
            ('/__pycache__/' in root) or 
            ('/teller.egg-info/' in root)):
            continue
            
        for file in files:
            if file.endswith('.py') and file != 'modern_typing.py':
                filepath = os.path.join(root, file)
                
                try:
                    if update_file(filepath):
                        updated_files.append(filepath)
                    else:
                        skipped_files.append(filepath)
                except Exception as e:
                    print(f"Error processing {filepath}: {e}")
    
    return updated_files, skipped_files

def main():
    """Run the script with command line arguments."""
    if len(sys.argv) > 1:
        # Process specific files or directories
        for path in sys.argv[1:]:
            if os.path.isfile(path) and path.endswith('.py'):
                if update_file(path):
                    print(f"Updated: {path}")
                else:
                    print(f"No changes needed: {path}")
            elif os.path.isdir(path):
                updated, _ = scan_directory(path)
                print(f"\nUpdated {len(updated)} files in {path}:")
                for file in updated:
                    print(f"  - {file}")
            else:
                print(f"Skipping {path} - not a Python file or directory")
    else:
        # Process current directory
        updated, skipped = scan_directory()
        print(f"\nUpdated {len(updated)} files:")
        for file in updated:
            print(f"  - {file}")
        
        print(f"\nSkipped {len(skipped)} files (no changes needed)")

if __name__ == "__main__":
    main() 