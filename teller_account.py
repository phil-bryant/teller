from dataclasses import dataclass, field
from sqlalchemy import String, Enum, ForeignKey, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_institution import TellerInstitution
from teller_account_links import TellerAccountLinks
from teller_enums import TellerAccountType, TellerAccountSubtype, TellerAccountStatus
from teller_account_details import TellerAccountDetails
from teller_account_balances import TellerAccountBalances
from teller_transaction import TellerTransaction
from typing import List, Optional
from datetime import datetime

@dataclass
class TellerAccount(TellerObject): ## https://teller.io/docs/api/accounts
    currency: Mapped[str] = mapped_column(String(3))
    enrollment_id: Mapped[str] = mapped_column(String)
    id: Mapped[str] = mapped_column(String, primary_key=True, name="account_id")
    institution: Mapped[TellerInstitution] = relationship(foreign_keys="institution.institution_id")
    last_four: Mapped[str] = mapped_column(String(4))
    links: Mapped[TellerAccountLinks] = relationship(foreign_keys="account_links.account_links_id")
    name: Mapped[str] = mapped_column(String, unique=True)
    type: Mapped[TellerAccountType] = mapped_column(Enum(TellerAccountType))
    subtype: Mapped[TellerAccountSubtype] = mapped_column(Enum(TellerAccountSubtype))
    status: Mapped[TellerAccountStatus] = mapped_column(Enum(TellerAccountStatus))
    details: Mapped[Optional[TellerAccountDetails]] = relationship(back_populates="account")
    balances: Mapped[Optional[TellerAccountBalances]] = relationship(back_populates="account")
    transactions: Mapped[List[TellerTransaction]] = relationship(back_populates="account")

    def institution_name(self) -> str:
        return self.institution.name if self.institution else ""
    
    def get_details(self) -> TellerAccountDetails:
        self.details = TellerAccountDetails(self._api_client.get(self.links.details))
        return self.details
    
    def get_transactions(self, count: int = None) -> list[TellerTransaction]:
        self.transactions = [TellerTransaction(td) for td in self._api_client.get(self.links.transactions, {'count': count} if count else {})]
        return self.transactions