#! /usr/bin/env python3
from typing import Annotated, Dict, List
# pyright: reportInvalidTypeForm=false
an = Annotated[float, {"min_value": 0, "required": True}]

print(an)

# Type annotations using Dict and List
def process_data(user_data: Dict[str, str], numbers: List[int]) -> List[str]:
    # Actual objects using dict and list
    result = []
    for key in user_data.keys():
        result.append(f"{key}: {user_data[key]}")
    return result

# Usage
data: Dict[str, str] = {"name": "Alice", "age": "30"}  # Type annotation
numbers: List[int] = [1, 2, 3]  # Type annotation

my_dict = {}  # Creates actual dict object
my_list = []  # Creates actual list object