#! /usr/bin/env python3
from teller_api_client_type import TellerAPIClient

class TellerMetaObject(type):
    def __call__(cls, *args, **kwargs):
        if not args:
            return super().__call__()
        
        arg = args[0]
        
        handler_method = cls._get_handler_for_type(type(arg))
        if handler_method:
            return handler_method(cls, arg)
            
        return super().__call__(*args, **kwargs)
    
    @classmethod
    def _get_handler_for_type(cls, arg_type):
        handlers = {
            TellerAPIClient: cls._handle_api_client,
            dict: cls._handle_dict,
            list: cls._handle_list
        }
        
        for registered_type, handler in handlers.items():
            if issubclass(arg_type, registered_type):
                return handler
                
        return None
    
    @classmethod
    def _handle_api_client(cls, self, api_client):
        print(f"TellerMetaObject.__call__ {self} {api_client}")
        self._api_client = api_client
        response = self._api_client.get(self._path)
        print(f"calling with {type(response)}")
        return self.__call__(response)
    
    @classmethod
    def _handle_dict(cls, self, api_data):
        print(f"TellerMetaObject.__call__ {self} dict")
        return super(TellerMetaObject, self).__call__(api_data)
    
    @classmethod
    def _handle_list(cls, self, api_data_list):
        print(f"TellerMetaObject.__call__ {self} list")
        objects = []
        for api_data_item in api_data_list:
            if isinstance(api_data_item, dict):
                print(f"calling with {type(api_data_item)}")
                obj = self.__call__(api_data_item)
                objects.append(obj)
        return objects 