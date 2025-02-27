#!/usr/bin/env python3
import os
import re
import sys

def update_file(filepath):
    """Update Optional[T] to T | None in a Python file."""
    with open(filepath, 'r') as file:
        content = file.read()
    
    original_content = content
    
    # Replace imports of Optional
    if 'from typing import Optional' in content or 'from typing import ' in content and ', Optional' in content:
        # Remove Optional from imports
        content = re.sub(r'from typing import ([^,\n]*, )Optional([,\n]|$)', r'from typing import \1\2', content)
        content = re.sub(r'from typing import ([^,\n]*), Optional([,\n]|$)', r'from typing import \1\2', content)
        content = re.sub(r'from typing import Optional([,\n]|$)', r'\1', content)
        
        # Clean up commas in imports
        content = re.sub(r'from typing import ,', r'from typing import ', content)
        content = re.sub(r'from typing import ([^,\n]*), ([,\n]|$)', r'from typing import \1\2', content)
        content = re.sub(r'from typing import \s*\n', r'', content)
    
    # Replace type annotations
    optional_pattern = r'Optional\[([^\[\]]+)\]'
    
    def replace_optional(match):
        type_name = match.group(1).strip()
        return f"{type_name} | None"
    
    content = re.sub(optional_pattern, replace_optional, content)
    
    # Handle nested Optional cases with recursion
    while 'Optional[' in content:
        content = re.sub(optional_pattern, replace_optional, content)
    
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
            if file.endswith('.py') and file != 'modernize_optional.py':
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