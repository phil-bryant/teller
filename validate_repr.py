#!/usr/bin/env python3

from teller_object_field import TellerObjectField

def main():
    """Test that TellerObjectField class behaves correctly with the added __repr__ method."""
    
    # Create a mock API data dictionary
    api_data = {
        "id": "acc_123456",
        "amount": "123.45",
        "date": "2023-05-15"
    }
    
    # Use the simplest constructor signature
    field1 = TellerObjectField(name="id", type_=str, api_data=api_data)
    
    # Use a constructor with metadata
    field2 = TellerObjectField(
        name="amount", 
        type_=str,  # Using str instead of Decimal for simplicity
        api_data=api_data, 
        metadata={"__str__": True}
    )
    
    # Use a constructor with api_name in metadata
    field3 = TellerObjectField(
        name="transaction_date", 
        type_=str,  # Using str instead of date for simplicity
        api_data=api_data,
        metadata={"api_name": "date", "__str__": True}
    )
    
    # Test the new __repr__ method
    print("Testing __repr__ for field1:")
    print(f"  {repr(field1)}")
    
    print("\nTesting __repr__ for field2:")
    print(f"  {repr(field2)}")
    
    print("\nTesting __repr__ for field3:")
    print(f"  {repr(field3)}")
    
    # Test that the basic functionality still works
    print("\nTesting basic functionality:")
    print(f"  field1.name = {field1.name}")
    print(f"  field1.type_ = {field1.type_}")
    print(f"  field1.value = {field1.value}")
    print(f"  field1.metadata = {field1.metadata}")
    
    print(f"  field2.name = {field2.name}")
    print(f"  field2.value = {field2.value}")
    
    # Test setting values
    field1.value = "new_acc_123456"
    print(f"\nAfter setting field1.value = 'new_acc_123456':")
    print(f"  field1.value = {field1.value}")
    print(f"  field1 = {field1}")
    
    # Success if we got this far without errors
    print("\nTest completed successfully!")
    
if __name__ == "__main__":
    main() 