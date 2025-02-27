#! /usr/bin/env python3
import os
import subprocess
import sys
from object_inspector import load_snapshot, compare_snapshots

def main():
    original_file = 'original_objects_snapshot.pickle'
    new_file = 'new_objects_snapshot.pickle'
    
    # Load the original snapshot
    print(f"Loading original snapshot...")
    original_objects = load_snapshot(original_file)
    print(f"Loaded original snapshot with {len(original_objects)} objects.")
    
    # Run teller_api_client to create new objects
    print("Running teller_api_client.py to create new objects...")
    result = subprocess.run(['python3', 'teller_api_client_validate.py'], 
                           capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running teller_api_client_validate.py: {result.stderr}")
        return 1
    
    # Print the output from the client
    print(result.stdout)
    
    # Load the new snapshot
    new_objects = load_snapshot(new_file)
    print(f"Loaded new snapshot with {len(new_objects)} objects.")
    
    # Compare the snapshots
    differences = compare_snapshots(original_objects, new_objects)
    
    if not differences:
        print("SUCCESS: Original and refactored implementations produce identical objects!")
        return 0
    else:
        print("FAILURE: Differences detected between original and refactored implementations:")
        for diff in differences[:20]:  # Limit to first 20 differences to avoid excessive output
            print(f"- {diff}")
        if len(differences) > 20:
            print(f"... and {len(differences) - 20} more differences")
        return 1

if __name__ == "__main__":
    sys.exit(main()) 