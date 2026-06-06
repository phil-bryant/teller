from dataclasses import dataclass, fields
from sqlalchemy.orm import declared_attr, mapped_column, Mapped
from sqlalchemy import DateTime
from typing import ClassVar
from datetime import datetime, timezone
import typing
import structlog
import re
from .teller_base import Base

log = structlog.get_logger()

class TimestampMixin:
    # #R001: Shared timestamp columns for Teller ORM models.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda *_: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda *_: datetime.now(timezone.utc),
        onupdate=lambda *_: datetime.now(timezone.utc),
    )

@dataclass
class TellerObject(Base, TimestampMixin):
    __abstract__ = True
    __allow_unmapped__ = True
    _api_data: ClassVar[dict]
    _api_client: ClassVar[any] = None
    # #R001: All subclasses live in the teller schema.
    __table_args__ = {"schema": "teller"}
    
    @classmethod
    # #R010: Class-level API client injection.
    def set_api_client(cls, client):
        cls._api_client = client
    
    # #R015: Initialize from optional API payload and trigger hydration.
    def __init__(self, api_data=None):
        log.debug("TellerObject.__init__", class_name=self.__class__.__name__, api_data=api_data)
        super().__init__()
        if api_data:
            self._api_data = api_data
            self.__post_init__()

    @declared_attr
    # #R005: Derive snake_case table names from Teller* class names.
    def __tablename__(cls) -> str:
        name = cls.__name__.replace('Teller', '')
        return re.sub('(?!^)([A-Z][a-z]+)', r'_\1', name).lower()

    # #R020: Map API payload keys using optional column api_name aliases.
    def _mapped_api_data(self):
        ## Handle cases where python objects need field names differing from API field names. See next comment.
        from sqlalchemy import inspect as sa_inspect
        try:
            col_info = {a.key: a.columns[0].info for a in sa_inspect(self.__class__).column_attrs}
        except Exception:
            col_info = {}
        log.debug("TellerObject._mapped_api_data", class_name=self.__class__.__name__, api_data=self._api_data)
        return {f.name: self._api_data[col_info.get(f.name, {}).get("api_name", f.name)]
                for f in fields(self.__class__)
                if col_info.get(f.name, {}).get("api_name", f.name) in self._api_data}

    # #R025: Unpack list/scalar annotations for hydration type coercion.
    def _unpack_annotation(self, ann):
        args = typing.get_args(ann)
        inner = args[0] if args else ann
        inner_origin, inner_args = typing.get_origin(inner), typing.get_args(inner)
        return (inner_args[0], True) if (inner_origin is list and inner_args) else (inner, False)

    # #R025: Coerce API data into annotated field types when possible.
    def __post_init__(self):
        ## Use python introspection to otherwise simply mirror the Teller API Objects as python objects.
        try:
            hints = typing.get_type_hints(self.__class__)
        except Exception:
            hints = dict(self.__annotations__)
        log.debug("TellerObject.__post_init__", class_name=self.__class__.__name__, api_data=self._api_data, mapped_api_data=self._mapped_api_data())
        for key, value in self._mapped_api_data().items():
            if hasattr(self, key) and value is not None:
                target, is_list = self._unpack_annotation(hints.get(key, type(value)))
                log.debug("TellerObject.setting_attr", class_name=self.__class__.__name__, key=key, value=value, target=target, is_list=is_list)
                try:
                    setattr(self, key, [target(x) for x in value] if (is_list and isinstance(value, list)) else target(value)) ## Fails if key is type list but works if key is type TellerList!
                except (TypeError, ValueError, KeyError):
                    setattr(self, key, value)

    # #R030: Collect dataclass fields marked for debug-string rendering.
    def _str_field_names(self):
        return [field.name for field in fields(self.__class__) if field.metadata.get("__str__", False)]

    # #R030: Include selected fields and API payload in debug string output.
    def __str__(self):
        return f"{self.__class__.__name__}({', '.join(f'{getattr(self, name)}' for name in self._str_field_names())}):_api_data={self._api_data}"