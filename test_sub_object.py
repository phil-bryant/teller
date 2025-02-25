#! /usr/bin/env python3
from test_print import print_me
from test_object import Obj

class SubObj(Obj):
    _path: str = "/sub1"

    def __new__(cls, *args, **kwargs):
        print('SubObj.__new__...')
        instance = super().__new__(cls, *args, **kwargs)
        print(instance)
        print_me("SubObj.__new__", cls, super(), *args, **kwargs)
        return instance

    def __init__(self, *args, **kwargs):
        print('SubObj.__init__...')
        super().__init__(*args, **kwargs)
        print_me("SubObj.__init__", self, super(), *args, **kwargs)