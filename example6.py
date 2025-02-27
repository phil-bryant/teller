#! /usr/bin/env python3
from typing import _AnnotatedAlias

# pyright: reportInvalidTypeForm=false

setattr(_AnnotatedAlias, '__init_subclass__', lambda *args, **kwargs: None)

class APIField2(_AnnotatedAlias):
    def noop(self): pass

class Product:
    price: APIField2(float, {"min_value": 0, "required": True}) = 0.0
    
    def __init__(self, price: float):
        self.price = price

    def print_annotations(self) -> None:
        for field, annotation in self.__annotations__.items():
            print(field, annotation)
            for k, v in annotation.__metadata__[0].items():
                print(k, v)

p = Product(100)
p.print_annotations()