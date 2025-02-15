#! /usr/bin/env python3

class DynamicObject:
    def __init__(self):
        self._data = {}

    def __getattribute__(self, name):
        try:
            return super().__getattribute__(name)
        except AttributeError:
            data = super().__getattribute__('_data')
            value = data.get(name)
            if value is None:
                if name.startswith('_'):
                    raise AttributeError(name)
                handler = lambda *args: f"Handled unknown method: {name} with args: {args}"
                return handler() if not name.endswith('method') else handler
            return value

    def __setattr__(self, name, value):
        if name == '_data':
            super().__setattr__(name, value)
            return
        print(f"Intercepted setting {name} = {value}")
        self._data[name] = value

obj = DynamicObject()
result = obj.unknown_method(1, 2, 3)
print(result)  # Outputs: Handled unknown method: unknown_method with args: (1, 2, 3)
result2 = obj.some_property
print(result2)
obj.another_property = "test value"
print(obj.another_property)