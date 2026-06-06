from sqlalchemy.orm import registry, DeclarativeBase

#R600: Expose shared SQLAlchemy declarative registry and metadata base.
#R605: Bind declarative subclasses to the shared base registry.
class Base(DeclarativeBase):
    registry = registry() 