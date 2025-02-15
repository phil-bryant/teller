#! /usr/bin/env python3
from typing import Annotated

# pyright: reportInvalidTypeForm=false
    
class Product:
    name: Annotated[str, {"max_length": 100, "required": True}] = "foo"
    price: Annotated[float, {"min_value": 0, "required": True}] = 0.0
    
    def __init__(self, name: str, price: float):
        self.name = name
        self.price = price

    def print_annotations(self) -> None:
        for field, annotation in self.__annotations__.items():
            metadata = annotation.__metadata__[0]
            for k, v in metadata.items():
                print(field, k, v)

p = Product("test", 100)
p.print_annotations()