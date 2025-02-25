#!/usr/bin/env python3
import re
import os
import sys

def fix_file(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Check if the file contains _set_field calls
    if '_set_field(' not in content:
        print(f"Skipping {file_path} - no _set_field calls")
        return
    
    original_content = content
    
    # Fix trailing commas in metadata dictionaries
    content = re.sub(r'_set_field\((.*?), {(.*?)}, \)', r'_set_field(\1, {\2})', content)
    
    # Remove empty metadata dictionaries
    content = re.sub(r'_set_field\("([^"]+)", ([^,]+), ([^,]+), {}\)', r'_set_field("\1", \2, \3)', content)
    
    # Set database-only fields to use None instead of api_data
    # This is a heuristic - fields with _id suffix and pk=True are likely database-only
    id_fields_pattern = r'_set_field\("([^"]+_id)", ([^,]+), api_data, ({"pk": True(?:, [^}]+)?})\)'
    content = re.sub(id_fields_pattern, r'_set_field("\1", \2, None, \3)', content)
    
    if content != original_content:
        # Write the modified content back to the file
        with open(file_path, 'w') as f:
            f.write(content)
        print(f"Fixed {file_path}")
    else:
        print(f"No changes needed for {file_path}")

def main():
    if len(sys.argv) > 1:
        # Fix specific files
        for file_path in sys.argv[1:]:
            if os.path.isfile(file_path):
                fix_file(file_path)
    else:
        # Find all Python files
        for file in os.listdir('.'):
            if file.endswith('.py') and file != 'fix_set_field.py' and file != 'convert_annotations.py':
                fix_file(file)

if __name__ == "__main__":
    main() 