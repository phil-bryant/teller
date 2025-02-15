#! /usr/bin/env python3
from typing import Annotated, Optional

class Product:
    def __init__(self, name: Optional[str] = None, price: Optional[float] = None):
        self.name: Annotated[str, {"max_length": 100}] = name
        self.price: Annotated[float, {"min_value": 0}] = price

    def print_vars(self) -> None:
        for key, value in self.__dict__.items():
            print(f"key={key}")
            print(f"value={value}")
            print(f"getattr(self, key)={getattr(self, key)}")
            print(f"type(getattr(self, key))={type(getattr(self, key))}")

p = Product()
p.print_vars()