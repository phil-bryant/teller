#! /usr/bin/env python3

class DynamicParent:
    def unknown_method(self, a: int, b: int, c: int) -> int:
        return a + b + c

class DynamicObject(DynamicParent):
    def __getattribute__(self, name):
        #try:
            print("bozo")
            return super().__getattribute__(name)
        #except AttributeError:
         #   handler = lambda *args: f"Handled unknown method: {name} with args: {args}"
           # return handler

    def __setattr__(self, name, value):
        print(f"Intercepted setting {name} = {value}")

    def unknown_method(self, a: int, b: int, c: int) -> int:
        return c - b - a
    
obj = DynamicObject()
result = obj.unknown_method(1, 2, 3)
print(result)  # Outputs: Handled unknown method: unknown_method with args: (1, 2, 3)
result2 = obj.another_unknown_method(1, 2, 3)
print(result2)
obj.another_property = "test value"
print(obj.another_property)