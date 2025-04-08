#! /usrbin/env python3
from abc import ABC
from .teller_meta_object import TellerMetaObject

class TellerObject(metaclass=TellerMetaObject): ## https://teller.io/docs/api
    ...