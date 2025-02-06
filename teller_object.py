from dataclasses import dataclass, fields
from sqlalchemy.orm import DeclarativeBase, declared_attr, mapped_column, Mapped
from sqlalchemy import MetaData, DateTime
from typing import ClassVar
from datetime import datetime
import structlog
import re
from teller_base import Base

log = structlog.get_logger()

class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

@dataclass
class TellerObject(Base, TimestampMixin):
    __abstract__ = True
    __allow_unmapped__ = True
    _api_data: ClassVar[dict]
    _api_client: ClassVar[any] = None
    __table_args__ = {"schema": "teller"}
    
    @classmethod
    def set_api_client(cls, client):
        cls._api_client = client
    
    def __init__(self, api_data=None):
        log.debug("TellerObject.__init__", class_name=self.__class__.__name__, api_data=api_data)
        super().__init__()
        if api_data:
            self._api_data = api_data
            self.__post_init__()

    @declared_attr
    def __tablename__(cls) -> str:
        name = cls.__name__.replace('Teller', '')
        return re.sub('(?!^)([A-Z][a-z]+)', r'_\1', name).lower()

    def _mapped_api_data(self):
        ## Handle cases where python objects need field names differing from API field names. See next comment.
        log.debug("TellerObject._mapped_api_data", class_name=self.__class__.__name__, api_data=self._api_data)
        return {field.name: self._api_data[field.metadata.get("api_name", field.name)]
                for field in fields(self.__class__)
                if field.metadata.get("api_name", field.name) in self._api_data}

    def __post_init__(self):
        ## Use python introspection to otherwise simply mirror the Teller API Objects as python objects.
        log.debug("TellerObject.__post_init__", class_name=self.__class__.__name__, api_data=self._api_data, mapped_api_data=self._mapped_api_data())
        for key, value in self._mapped_api_data().items():
            if hasattr(self, key) and value is not None:
                log.debug("TellerObject.setting_attr", class_name=self.__class__.__name__, key=key, value=value, annotation=self.__annotations__[key])
                setattr(self, key, self.__annotations__[key](value)) ## Fails if key is type list but works if key is type TellerList!

    def _str_field_names(self):
        return [field.name for field in fields(self.__class__) if field.metadata.get("__str__", False)]

    def __str__(self):
        return f"{self.__class__.__name__}({', '.join(f'{getattr(self, name)}' for name in self._str_field_names())}):_api_data={self._api_data}"