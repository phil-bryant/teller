from typing import Any, Type

class Field:
    def __init__(self, name: str, type_: Type, value: Any = None, metadata: dict = None, default: any = None):
        print("Field.__init__")
        self.name = name
        self.type_ = type_
        self.value = value
        self.metadata = metadata
        self.default = default

    def __set__(self, instance, value):
        print("Field.__set__")
        self.value = value

    def __get__(self, instance, owner):
        print("Field.__get__")
        return self.value