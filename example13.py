#! /usr/bin/env python3
# pyright: reportInvalidTypeForm=false
from typing import Annotated

class APIField:
    def __class_getitem__(cls, params): return cls(*params)
    
    def __init__(self, type_arg, metadata):
        self.__origin__ = APIField
        self.__args__ = (type_arg, metadata | {"api_name": "foo"})

class Product:
    #category: str = "software"
    
    price: Annotated[float, {"min_value": 0, "required": True}]
    
    def __init__(self, name, price: float):
        self.name: Annotated[str, {"max_length": 100, "required": True}] = name
        self.price = price

    def print_vars(self) -> None:
        for each in self.__dict__:
            print(f"{each}: {type(getattr(self, each)).__name__} = {getattr(self, each)}")
        print("foo")
            
        for field, annotation in self.__annotations__.items():
            print(f"{field} type: {annotation.__args__[0].__name__}")
            if hasattr(annotation, '__origin__') and annotation.__origin__ is APIField:
                for k, v in annotation.__args__[1].items():
                    print(f"{field} {k}: {v}")

p = Product("test", 100.0)
p.print_vars()