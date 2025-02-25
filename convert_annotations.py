#!/usr/bin/env python3
import re
import os
import sys

def convert_file(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Check if the file imports Annotation
    if 'from annotation import Annotation' not in content:
        print(f"Skipping {file_path} - no Annotation import")
        return
    
    # Extract class name
    class_match = re.search(r'class (\w+)\(TellerObject\)', content)
    if not class_match:
        print(f"Skipping {file_path} - no TellerObject subclass found")
        return
    
    class_name = class_match.group(1)
    print(f"Converting {class_name} in {file_path}")
    
    # Find all Annotation declarations
    annotation_pattern = r'(\w+): Annotation\[(\w+), \(({.*?}(?:, )?)\)\s?\] = (.*?)$'
    annotations = re.findall(annotation_pattern, content, re.MULTILINE)
    
    # Check if there's already an __init__ method
    init_exists = '__init__' in content
    
    # Remove the Annotation import
    content = re.sub(r'from annotation import Annotation\n', '', content)
    
    # Remove all Annotation declarations
    for field_name, field_type, metadata, default_value in annotations:
        content = re.sub(r'^\s*' + field_name + r': Annotation\[.*?\] = .*?$', '', content, flags=re.MULTILINE)
    
    # Add or modify __init__ method
    init_code = f"    def __init__(self, api_data: dict):\n        super().__init__()\n"
    for field_name, field_type, metadata, default_value in annotations:
        init_code += f"        self._set_field(\"{field_name}\", {field_type}, api_data, {metadata})\n"
    
    if init_exists:
        # Replace existing __init__ method
        content = re.sub(r'    def __init__\(self, .*?\):\n.*?super\(\).__init__\(.*?\)', init_code.strip(), content, flags=re.DOTALL)
    else:
        # Add new __init__ method after class declaration
        content = re.sub(r'(class ' + class_name + r'\(TellerObject\):.*?)(\n\n|\n    def|\Z)', r'\1\n\n' + init_code + r'\2', content, flags=re.DOTALL)
    
    # Clean up empty lines
    content = re.sub(r'\n\n\n+', '\n\n', content)
    
    # Write the modified content back to the file
    with open(file_path, 'w') as f:
        f.write(content)
    
    print(f"Converted {file_path}")

def main():
    if len(sys.argv) > 1:
        # Convert specific files
        for file_path in sys.argv[1:]:
            if os.path.isfile(file_path):
                convert_file(file_path)
    else:
        # Find all Python files that import Annotation
        for file in os.listdir('.'):
            if file.endswith('.py') and file != 'annotation.py' and file != 'convert_annotations.py':
                convert_file(file)

if __name__ == "__main__":
    main() 