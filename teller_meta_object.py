#! /usr/bin/env python3
from teller_api_client_type import TellerAPIClient

class TellerMetaObject(type):
    def __call__(cls, *args, **kwargs):
        print(f"TellerMetaObject.__call__ {cls} {args}")
        for arg in args:
            print(f"receiving with {type(arg)}")
            if isinstance(arg, TellerAPIClient): 
                cls._api_client = arg
                result = cls._api_client.get(cls._path)
                print(f"calling with {type(result)}")
                return cls.__call__(result)
            elif isinstance(arg, list):
                objects = []
                for api_data_item in arg:
                    if isinstance(api_data_item, dict):
                        print(f"calling with {type(api_data_item)}")
                        obj = super().__call__(api_data_item)
                        objects.append(obj)
                    else:
                        pass
                return objects
            else:
                return super().__call__(arg)
