#! /usr/bin/env python3
import inspect as inspector

def print_class(cls):
    print(f"    cls = {cls.__name__}")

def print_instance(instance):
    print(f"    self = {instance.__class__.__name__}")

def print_sup(sup):
    print(f"    sup = {sup}")

def print_args(args, kwargs):
    for i, arg in enumerate(args):
        if isinstance(arg, dict):
            for k, v in arg.items():
                print(f"    arg[{i}][{k}] = {v}")
        else:
            print(f"    arg[{i}] = {arg}")
    if kwargs:
        print("    kwargs:")
        for key, value in kwargs.items():
            print(f"        {key}: {value}")

def print_me(label, classorinstance, sup, *args, **kwargs):
    print(f"{label}: ")
    if isinstance(classorinstance, type):
        print_class(classorinstance)
    else:
        print_instance(classorinstance)
    print_sup(sup)
    print_args(args, kwargs)
    print()

    ## class type
    ## def __init__(self, o: object, /) -> None: ...
    ## def __init__(self, name: str, bases: tuple[type, ...], dict: dict[str, Any], /, **kwds: Any) -> None: ...
    ## 
    ## def __new__(cls, o: object, /) -> type: ...
    ## def __new__(cls: type[_typeshed.Self], name: str, bases: tuple[type, ...], namespace: dict[str, Any], /, 
    ##               **kwds: Any) -> _typeshed.Self: ...

    ## class super:
    ## def __init__(self, t: Any, obj: Any, /) -> None: ...
    ## def __init__(self, t: Any, /) -> None: ...
    ## def __init__(self) -> None: ...