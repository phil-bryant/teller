#! /usr/bin/env python3
from typing import Annotated

# pyright: reportInvalidTypeForm=false
setattr(Annotated, '__init_subclass__', lambda *args, **kwargs: None)
setattr(Annotated, '__mro_entries__', lambda bases, *args: ())
setattr(Annotated, '__new__', lambda *args: print("foo1"))

class APIField(Annotated, _root=True):
    def __new__(cls, type_arg, metadata, *args, **kwargs):
        print("foo2")
        return super().__new__(cls, type_arg, metadata, *args, **kwargs)
    
    def __init__(self, type_arg, metadata, *args, **kwargs):
        print("foo3")
        #self.__metadata__[0]["api_name"] = "foo"
    
    def __init_subclass__(cls, *args, **kwargs):
        print("foo4")

    def __class_getitem__(cls, params):
        print("foo5")  # This should actually get called
        return super().__class_getitem__(params)

    
class Product:
    name: APIField[str, {"max_length": 100, "required": True}] = "foo6"
    price: APIField[float, {"min_value": 0, "required": True}] = 0.0
    
    def __init__(self, name: str, price: float):
        self.name = name
        self.price = price

    def print_annotations(self) -> None:
        for field, annotation in self.__annotations__.items():
            for k, v in annotation.__metadata__[0].items():
                print(field, k, v)

p = Product("test", 100)
p.print_annotations()