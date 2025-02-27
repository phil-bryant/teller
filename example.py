#! /usr/bin/env python3
from typing import Annotated
# pyright: reportInvalidTypeForm=false
an = Annotated[float, {"min_value": 0, "required": True}]

print(an)

# Type annotations using Dict and List
def process_data(user_data: dict[str, str], numbers: list[int]) -> list[str]:
    # Actual objects using dict and list
    result = []
    for key in user_data.keys():
        result.append(f"{key}: {user_data[key]}")
    return result

# Usage
data: dict[str, str] = {"name": "Alice", "age": "30"}  # Type annotation
numbers: list[int] = [1, 2, 3]  # Type annotation

my_dict = {}  # Creates actual dict object
my_list = []  # Creates actual list object