#! /usr/bin/env python3
# pyright: reportInvalidTypeForm=false

class APIField:
    def __class_getitem__(cls, params): return cls(*params)

    def __init__(self, type_arg, metadata):
        self.__origin__ = type_arg
        self.__metadata__ = (metadata,) if not isinstance(metadata, tuple) else metadata
        self.__args__ = (type_arg,) + self.__metadata__

class Product:
    #category: str = "software"
    names: APIField[list[str], {"max_length": 100, "required": True}]
    price: APIField[float, {"min_value": 0, "required": True}]
    
    def __init__(self, names: list[str], price: float):
        self.name = names
        self.price = price

    def print_vars(self) -> None:
          for field, annotation in self.__annotations__.items():
            print(f"field: {field} annotation: {annotation.__class__.__name__} origin: {annotation.__origin__} args: {annotation.__args__} metadata: {annotation.__metadata__}")
            for k, v in annotation.__metadata__[0].items():
                print(field, k, v)

p = Product(["test", "test2"], 100.0)
p.print_vars()