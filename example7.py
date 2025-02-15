#! /usr/bin/env python3
from typing import Annotated, _AnnotatedAlias

# pyright: reportInvalidTypeForm=false

setattr(Annotated, '__init_subclass__', lambda *args, **kwargs: None)
# setattr(Annotated, '__new__', lambda cls, origin, metadata: _AnnotatedAlias(origin, metadata))

class APIField(Annotated):
    def noop(self): pass
    #def __init__(self, origin, metadata):
    #    super().__init__(origin, metadata)
    #    self.__metadata__[0]["api_name"] = "foo"
    
class Product:
    name: APIField[str, {"max_length": 100, "required": True}] = "foo"
    price: Annotated[float, {"min_value": 0, "required": True}] = 0.0
    
    def __init__(self, name: str, price: float):
        self.name = name
        self.price = price

    def print_annotations(self) -> None:
        for field, annotation in self.__annotations__.items():
            for k, v in annotation.__metadata__[0].items():
                print(field, k, v)

p = Product("test", 100)
p.print_annotations()