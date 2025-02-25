#! /usr/bin/env python3
from test_print import print_me
from test_meta_object import MetaObj

class Obj(metaclass=MetaObj):
    def __init__(self, *args, **kwargs):
        print('Obj.__init__...')
        super().__init__()
        print_me("Obj.__init__", self, super(), *args, **kwargs)