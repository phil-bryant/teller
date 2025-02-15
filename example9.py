#! /usr/bin/env python3
#from typing import Annotated

# pyright: reportInvalidTypeForm=false
#setattr(Annotated, '__init_subclass__', lambda *args, **kwargs: None)
#setattr(Annotated, '__mro_entries__', lambda bases, *args: ())
#setattr(Annotated, '__new__', lambda *args: print("foo1"))

class APIField:
    def __init__(self, type_arg, metadata):
        print("foo3")
        self.type_arg = type_arg
        self.metadata = metadata
    
    def __class_getitem__(cls, params):
        print("foo5")
        type_arg, metadata = params
        return cls(type_arg, metadata)
    
    def __get__(self, obj, objtype=None):
        print("foo2")
        if obj is None:
            return self
        return getattr(obj, f'_{self.type_arg.__name__}', None)
    
    def __set__(self, obj, value):
        setattr(obj, f'_{self.type_arg.__name__}', value)

class Product:
    name: APIField[str, {"max_length": 100, "required": True}]
    price: APIField[float, {"min_value": 0, "required": True}]
    
    def __init__(self, name: str, price: float):
        self.name = name
        self.price = price

    def print_annotations(self) -> None:
        for field, annotation in self.__annotations__.items():
            for k, v in annotation.metadata.items():
                print(field, k, v)

p = Product("test", 100)
p.print_annotations()