#! /usr/bin/env python3
import typing

setattr(typing.Annotated, '__init_subclass__', lambda *args, **kwargs: None)
class B(typing.Annotated):
    def __new__(cls, *args, **kwargs):
        return super(super().__thisclass__.__base__, cls).__new__(cls)    
    
    def __init_subclass__(cls, *args, **kwargs): pass

b = B()
print(b)