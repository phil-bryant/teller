#! /usr/bin/env python3
from teller_meta_object import TellerMetaObject
from test_teller_api_client import TestTellerAPIClient
, Any, List, Optional

class TestObject(metaclass=TellerMetaObject):
    _path = "/test-objects"
    
    def __init__(self, data: Optional[dict[str, Any]] = None):
        self.id = data.get("id") if data else None
        self.name = data.get("name") if data else "Unnamed"
        self.attributes = data.get("attributes", {}) if data else {}
        
    def __str__(self):
        return f"TestObject(id={self.id}, name={self.name}, attributes={self.attributes})"

def test_empty_call():
    print("\n=== Testing empty constructor ===")
    obj = TestObject()
    print(f"Result: {obj}")
    
def test_dict_call():
    print("\n=== Testing dictionary constructor ===")
    obj = TestObject({"id": "test-1", "name": "Test Object", "attributes": {"color": "blue"}})
    print(f"Result: {obj}")
    
def test_api_call():
    print("\n=== Testing API client constructor ===")
    # Simple response
    api_client1 = TestTellerAPIClient({"id": "api-1", "name": "API Object"})
    obj1 = TestObject(api_client1)
    print(f"Result (simple response): {obj1}")
    
    # List response
    list_response = [
        {"id": "api-list-1", "name": "API List Item 1"},
        {"id": "api-list-2", "name": "API List Item 2"}
    ]
    api_client2 = TestTellerAPIClient(list_response)
    obj_list = TestObject(api_client2)
    print(f"Result (list response): {obj_list}")
    
def test_list_call():
    print("\n=== Testing list constructor ===")
    list_data = [
        {"id": "list-1", "name": "List Item 1", "attributes": {"priority": "high"}},
        {"id": "list-2", "name": "List Item 2", "attributes": {"priority": "medium"}},
        {"id": "list-3", "name": "List Item 3", "attributes": {"priority": "low"}}
    ]
    obj_list = TestObject(list_data)
    print(f"Result: {obj_list}")
    for i, obj in enumerate(obj_list):
        print(f"  Item {i}: {obj}")

def main():
    print("Testing TellerMetaObject with multipledispatch overloading")
    
    test_empty_call()
    test_dict_call()
    test_api_call() 
    test_list_call()
    
    print("\nAll tests completed.")

if __name__ == "__main__":
    main() 