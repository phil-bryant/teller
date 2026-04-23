from datetime import date

class ISODate(date):
    def __new__(cls, datestr):
        return date.fromisoformat(datestr) 