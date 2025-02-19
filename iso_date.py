from datetime import date
from _pydatetime import MINYEAR

class ISODate(date):
    def __new__(cls, datestr):
        return date.fromisoformat(datestr or f"{MINYEAR:04d}-01-01")