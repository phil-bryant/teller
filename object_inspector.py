#! /usr/bin/env python3
import pickle
import inspect
import os
import re
from typing import Any, Dict, List, Set, Tuple

def get_object_details(obj):
    details = {
        'class': obj.__class__.__name__,
        'id': id(obj),
        'attrs': {}
    }
    
    for attr_name in dir(obj):
        if attr_name.startswith('__') or callable(getattr(obj, attr_name)):
            continue
        try:
            attr_value = getattr(obj, attr_name)
            details['attrs'][attr_name] = str(attr_value)
        except Exception as e:
            details['attrs'][attr_name] = f"Error accessing: {str(e)}"
    
    if hasattr(obj, '_fields'):
        details['fields'] = {}
        for field_name, field_obj in obj._fields.items():
            field_details = {
                'name': field_obj.name if hasattr(field_obj, 'name') else 'N/A',
                'type': field_obj.type_.__name__ if hasattr(field_obj, 'type_') else 'N/A',
                'value': str(field_obj.value) if hasattr(field_obj, 'value') else 'N/A',
                'api_name': field_obj.api_name if hasattr(field_obj, 'api_name') else 'N/A',
                'metadata': str(field_obj.metadata) if hasattr(field_obj, 'metadata') else 'N/A'
            }
            details['fields'][field_name] = field_details
    
    return details

def save_objects_snapshot(objects, filename='objects_snapshot.pickle'):
    details = []
    for obj in objects:
        details.append(get_object_details(obj))
    
    with open(filename, 'wb') as f:
        pickle.dump(details, f)
    
    print(f"Saved {len(details)} objects to {filename}")

def load_objects_snapshot(filename='objects_snapshot.pickle'):
    if not os.path.exists(filename):
        return []
        
    with open(filename, 'rb') as f:
        return pickle.load(f)

def _clean_memory_addresses(value: str) -> str:
    """Clean memory addresses from string representations."""
    if not isinstance(value, str):
        return value
    
    # Replace memory addresses in standard object representations
    value = re.sub(r' at 0x[0-9a-f]+', ' at 0xMEMADDRESS', value)
    
    # Also handle TellerObjectField specific representation format
    # From: TellerObjectField(name: type = value {'metadata'})
    # To: <teller_object_field.TellerObjectField object at 0xMEMADDRESS>
    if 'TellerObjectField(' in value:
        return '<teller_object_field.TellerObjectField object at 0xMEMADDRESS>'
    
    return value

def compare_snapshots(original_snapshot: List[Any], new_snapshot: List[Any]) -> List[str]:
    """Compare two snapshots and return a list of differences."""
    differences = []
    
    if len(original_snapshot) != len(new_snapshot):
        differences.append(f"Different number of objects: original={len(original_snapshot)}, new={len(new_snapshot)}")
        return differences
    
    for i, (original_obj, new_obj) in enumerate(zip(original_snapshot, new_snapshot)):
        # Check object types
        if type(original_obj).__name__ != type(new_obj).__name__:
            differences.append(f"Object {i}: Different types - original={type(original_obj).__name__}, new={type(new_obj).__name__}")
            continue
        
        # Compare attributes
        original_attrs = {key: value for key, value in original_obj.__dict__.items() if not key.startswith('_')}
        new_attrs = {key: value for key, value in new_obj.__dict__.items() if not key.startswith('_')}
        
        for key in set(original_attrs.keys()) | set(new_attrs.keys()):
            if key not in original_attrs:
                differences.append(f"Object {i}: Missing attribute '{key}' in original")
            elif key not in new_attrs:
                differences.append(f"Object {i}: Missing attribute '{key}' in new")
            elif _clean_memory_addresses(str(original_attrs[key])) != _clean_memory_addresses(str(new_attrs[key])):
                differences.append(f"Object {i}: Different attribute value for '{key}' - original={_clean_memory_addresses(str(original_attrs[key]))}, new={_clean_memory_addresses(str(new_attrs[key]))}")
        
        # Compare _fields specially since it appears to be a major source of differences
        if hasattr(original_obj, '_fields') and hasattr(new_obj, '_fields'):
            for field_name in set(original_obj._fields.keys()) | set(new_obj._fields.keys()):
                if field_name not in original_obj._fields:
                    differences.append(f"Object {i}: Missing field '{field_name}' in original")
                elif field_name not in new_obj._fields:
                    differences.append(f"Object {i}: Missing field '{field_name}' in new")
                else:
                    original_field = original_obj._fields[field_name]
                    new_field = new_obj._fields[field_name]
                    
                    original_field_str = _clean_memory_addresses(str(original_field))
                    new_field_str = _clean_memory_addresses(str(new_field))
                    
                    if original_field_str != new_field_str:
                        differences.append(f"Object {i}: Different field value for '{field_name}' - original={original_field_str}, new={new_field_str}")
    
    return differences

def load_snapshot(file_path: str) -> List[Any]:
    """Load objects from a pickle file."""
    with open(file_path, 'rb') as f:
        return pickle.load(f)

def save_snapshot(objects: List[Any], file_path: str) -> None:
    """Save objects to a pickle file."""
    with open(file_path, 'wb') as f:
        pickle.dump(objects, f)
    print(f"Saved {len(objects)} objects to {file_path}") 