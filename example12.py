#! /usr/bin/env python3
# pyright: reportInvalidTypeForm=false

class APIField:
    def __class_getitem__(cls, params): return cls(*params)
    
    def __init__(self, type_arg, metadata):
        self.type_arg = type_arg
        self.metadata = metadata | {"api_name": "foo"}

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