#! /usr/bin/env python3
from test_print import print_me
import inspect as inspect

class MetaObj(type):
    _path: str = ""
    _api_client = None

    def __call__(cls, *args, **kwargs):
        print('MetaObj.__call__...')
        instance = super().__call__(*args, **kwargs)
        print_me('MetaObj.__call__', cls, super(), *args, **kwargs)
        return instance
    
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