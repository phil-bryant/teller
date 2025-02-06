from sqlalchemy.orm import registry, DeclarativeBase

class Base(DeclarativeBase):
    registry = registry() 