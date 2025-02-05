from dataclasses import dataclass
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column
from teller_object import TellerObject

@dataclass
class TellerInstitution(TellerObject): ## https://teller.io/docs/api/institutions
    institution_id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String, unique=True) 