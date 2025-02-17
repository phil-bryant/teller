from typing import _type_repr

class Annotation:
    def __class_getitem__(cls, params): 
        print("annotation.__class_getitem__")
        return cls(*params)

    def __init__(self, type_arg, metadata):
        print("annotation.__init__")
        self.__origin__ = type_arg
        self.__metadata__ = (metadata,) if not isinstance(metadata, tuple) else metadata
        self.__args__ = (type_arg,) + self.__metadata__

    def __repr__(self):
        return f"{self.__class__.__name__}[{_type_repr(self.__origin__)}, {', '.join(repr(a) for a in self.__metadata__)}]"