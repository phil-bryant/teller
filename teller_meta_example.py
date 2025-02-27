#! /usr/bin/env python3
from teller_meta_object import TellerMetaObject
from teller_api_client_type import TellerAPIClient
from typing import Any

class ExampleAPIClient(TellerAPIClient):
    def get(self, path, params=None):
        print(f"ExampleAPIClient.get({path}, {params})")
        return [{"id": 1, "name": "Example 1"}, {"id": 2, "name": "Example 2"}]

class ExampleObject(metaclass=TellerMetaObject):
    _path = "/examples"
    
    def __init__(self, data=None):
        self.id = data.get("id") if data else None
        self.name = data.get("name") if data else None
    
    def __str__(self):
        return f"ExampleObject(id={self.id}, name={self.name})"

def main():
    print("\n1. Creating an empty object:")
    empty_obj = ExampleObject()
    print(f"Result: {empty_obj}")
    
    print("\n2. Creating an object from a dictionary:")
    dict_obj = ExampleObject({"id": 42, "name": "Dictionary Example"})
    print(f"Result: {dict_obj}")
    
    print("\n3. Creating object(s) via API client:")
    api_client = ExampleAPIClient()
    api_objects = ExampleObject(api_client)
    print(f"Result: {api_objects}")
    
    print("\n4. Creating objects from a list of dictionaries:")
    list_data = [
        {"id": 101, "name": "List Item 1"},
        {"id": 102, "name": "List Item 2"}
    ]
    list_objects = ExampleObject(list_data)
    print(f"Result: {list_objects}")

if __name__ == "__main__":
    main() 