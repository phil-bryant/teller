from field import Field
from typing import Optional, Any, get_args, get_origin, get_type_hints
from iso_date import ISODate
from inspect import signature
import inspect
class TellerObject: ## https://teller.io/docs/api    
    def __init__(self, api_client: Optional[Any] = None, api_data: Optional[dict] = None):
        sig = signature(self.__init__)
        params = locals()
        del params['self']
        del params['sig']
        for param_name, param_value in params.items():
            param_type = sig.parameters[param_name].annotation
            print(f"param_name={param_name} param_value={param_value}")
            print(f"param_type={param_type}")
            print(f"param_type.__origin__={param_type.__origin__}")
            print(f"param_type.__args__={param_type.__args__}")
            print(f"param_type.__class__={param_type.__class__}")
            print(f"param_type.__name__={param_type.__name__}")
            print(f"param_type.__module__={param_type.__module__}")
            print()


    def __init2__(self, api_client: Optional[Any] = None, api_data: Optional[dict] = None):
            print()
            print(f"Starting... {param_name}: {type(param_type)}, {param_type} param_type.__class__: {param_type.__class__}\n")
            try:
                print(f"\nsuccess: {param_name}: {param_type} {type(param_type)}param_type.__base__: {param_type.__base__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__bases__: {param_type.__bases__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__basicsize__: {param_type.__basicsize__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__dict__: {param_type.__dict__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__dictoffset__: {param_type.__dictoffset__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__flags__: {param_type.__flags__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__itemsize__: {param_type.__itemsize__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__module__: {param_type.__module__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__mro__: {param_type.__mro__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__name__: {param_type.__name__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__qualname__: {param_type.__qualname__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__flags__: {param_type.__flags__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__itemsize__: {param_type.__itemsize__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__module__: {param_type.__module__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__mro__: {param_type.__mro__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__name__: {param_type.__name__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            try:
                print(f"\nsuccess: param_type.__qualname__: {param_type.__qualname__}\n")
            except AttributeError as e:
                print(f"\nsuccess: param_type.__text_signature__: {param_type.__text_signature__}\n")
            except AttributeError as e:
                print(f"ex: {e} param_name: {param_name} type(param_type: {type(param_type)} param_type: {param_type}")
            print(f"That was {param_name}: {type(param_type)}, {param_type} param_type.__class__.__class__: {param_type.__class__.__class__}\n")
        #self._api_client = Field("api_client", Any, api_client, {"db": False})
        #self._api_data = Field("_api_data", dict, api_data, {"db": False})
        #self.created_at: Annotation[ISODate, ({"__str__": True}, )] = None
        #self.updated_at: Annotation[ISODate, ({"__str__": True}, )] = None

    def __str__(self):
        return f"{self.__class__.__name__}({', '.join(f'{getattr(self, name)}' for name in self._str_field_names())}):_api_data={self._api_data}"
