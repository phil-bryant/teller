#! /usr/bin/env python3
from teller_api_client_type import TellerAPIClient
from functools import singledispatchmethod, update_wrapper

class MetaDispatchMethod:
    def __init__(self, func):
        self.dispatcher = singledispatchmethod(func)
        update_wrapper(self, func)
        
    def register(self, cls, method=None):
        return self.dispatcher.register(cls, method)
        
    def __get__(self, obj, cls):
        def _method(*args, **kwargs):
            if not args:
                return self.dispatcher.__get__(obj, cls)()
            
            # Get the first argument's type
            arg_type = type(args[0])
            method = self.dispatcher.registry.get(arg_type)
            
            if method is not None:
                return method.__get__(obj, cls)(args[0])
            else:
                # Try to find a registered method for parent classes
                for registered_type, registered_method in self.dispatcher.registry.items():
                    if registered_type is not object and isinstance(args[0], registered_type):
                        return registered_method.__get__(obj, cls)(args[0])
            
            # Fall back to default implementation
            return self.dispatcher.__get__(obj, cls)(*args, **kwargs)
        
        update_wrapper(_method, self.dispatcher.func)
        return _method

class TellerMetaObject(type):
    @MetaDispatchMethod
    def __call__(cls, *args, **kwargs):
        return super().__call__()
    
    @__call__.register(TellerAPIClient)
    def _(cls, api_client):
        print(f"TellerMetaObject.__call__ {cls} {api_client}")
        cls._api_client = api_client
        response = cls._api_client.get(cls._path)
        print(f"calling with {type(response)}")
        return cls.__call__(response)
    
    @__call__.register(dict)
    def _(cls, api_data):
        print(f"TellerMetaObject.__call__ {cls} dict")
        return super().__call__(api_data)
    
    @__call__.register(list)
    def _(cls, api_data_list):
        print(f"TellerMetaObject.__call__ {cls} list")
        objects = []
        for api_data_item in api_data_list:
            if isinstance(api_data_item, dict):
                print(f"calling with {type(api_data_item)}")
                obj = cls.__call__(api_data_item)
                objects.append(obj)
        return objects 