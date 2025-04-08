#! /usr/bin/env python3

from typing import TypeAlias

class TellerAPIClient(object):
    ... 

TellerAPIClientType: TypeAlias = TellerAPIClient | None
APIDataType: TypeAlias = list | dict | None
APIDataValueType: TypeAlias = dict | str | None