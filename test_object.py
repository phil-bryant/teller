#! /usr/bin/env python3
from test_print import print_me
from test_meta_object import MetaObj

class Obj(metaclass=MetaObj):
    def __new__(cls, *args, **kwargs):
        print('Obj.__new__...')
        instance = super().__new__(cls)
        print(instance)
        print_me("Obj.__new__", cls, super(), *args, **kwargs)
        return instance

    def __init__(self, *args, **kwargs):
        print('Obj.__init__...')
        super().__init__()
        print_me("Obj.__init__", self, super(), *args, **kwargs)