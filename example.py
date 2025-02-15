#! /usr/bin/env python3
from typing import Annotated
# pyright: reportInvalidTypeForm=false
an = Annotated[float, {"min_value": 0, "required": True}]

print(an)