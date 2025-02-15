#! /usr/bin/env python3
from typing import Annotated, Any

# pyright: reportInvalidTypeForm=false

setattr(Annotated, '__init_subclass__', lambda *args, **kwargs: None)

class APIField(Annotated):
    def __init_subclass__(self, *args, **kwargs): pass

    def __new__(cls, type_arg, metadata, *args, **kwargs):
        super_instance = super(super().__thisclass__.__base__, cls).__new__(cls)
        instance = super_instance._class_getitem_inner(type_arg, metadata, *args, **kwargs)
        return instance

class Product:
    name: APIField(str, {"max_length": 100, "required": True}) = "foo"
    price: Annotated[float, {"min_value": 0, "required": True}] = 0.0
    
    def __init__(self, name: str, price: float):
        self.name = name
        self.price = price

    def print_annotations(self) -> None:
        for field, annotation in self.__annotations__.items():
            meta = getattr(annotation, '__metadata__', None)
            if meta:
                for m in meta:
                    for k, v in m.items():
                        print(field, k, v)

p = Product("test", 100)
p.print_annotations()