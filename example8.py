#! /usr/bin/env python3
from typing import _Final

class A:
    def __init__(self, value: int):
        self.value = value

a = A(1)
print(a.value)

class B(A, _Final, _root=True):
    def __init__(self, value: int):
        super().__init__(value)

b = B(2)
print(b.value)