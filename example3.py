#! /usr/bin/env python3
class A:
    def __new__(cls, *args, **kwargs):
        print("A.__new__")
        return super().__new__(cls)

class B(A):
    def __new__(cls, *args, **kwargs):
        print("B.__new__")
        return super().__new__(cls)

class C(B):
    def __new__(cls, *args, **kwargs):
        print("C.__new__")
        return super(super().__thisclass__.__base__, cls).__new__(cls)

c = C()
