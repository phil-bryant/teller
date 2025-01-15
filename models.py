from typing import Optional
from decimal import Decimal
from sqlalchemy import String, DateTime, ForeignKey, Enum, Numeric
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.sql import func
from sqlalchemy.dialects.postgresql import JSONB
from datetime import datetime
import enum

# Enum definitions matching PostgreSQL types from 02_create_enums.sql
class AccountType(str, enum.Enum):
    depository = "depository"
    credit = "credit"

class AccountSubtype(str, enum.Enum):
    checking = "checking"
    savings = "savings"
    money_market = "money_market"
    certificate_of_deposit = "certificate_of_deposit"
    treasury = "treasury"
    sweep = "sweep"
    credit_card = "credit_card"

class AccountStatus(str, enum.Enum):
    open = "open"
    closed = "closed"

class ProcessingStatus(str, enum.Enum):
    pending = "pending"
    complete = "complete"

class TransactionStatus(str, enum.Enum):
    posted = "posted"
    pending = "pending"

class CounterpartyType(str, enum.Enum):
    organization = "organization"
    person = "person"

class Base(DeclarativeBase):
    pass

class Institution(Base):
    __tablename__ = "institutions"
    __table_args__ = {"schema": "teller"}

    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.current_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), 
        server_default=func.current_timestamp(),
        onupdate=func.current_timestamp()
    )

class Account(Base):
    __tablename__ = "accounts"
    __table_args__ = {"schema": "teller"}

    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    enrollment_id: Mapped[str] = mapped_column(String(50), nullable=False)
    institution_id: Mapped[str] = mapped_column(
        ForeignKey("teller.institutions.id"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    type: Mapped[str] = mapped_column(
        Enum(AccountType, schema="teller", name="account_type", native_enum=True),
        nullable=False
    )
    subtype: Mapped[str] = mapped_column(
        Enum(AccountSubtype, schema="teller", name="account_subtype", native_enum=True),
        nullable=False
    )
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    last_four: Mapped[str] = mapped_column(String(4), nullable=False)
    status: Mapped[str] = mapped_column(
        Enum(AccountStatus, schema="teller", name="account_status", native_enum=True),
        nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.current_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.current_timestamp(),
        onupdate=func.current_timestamp()
    )

class AccountBalance(Base):
    __tablename__ = "account_balances"
    __table_args__ = {"schema": "teller"}

    account_id: Mapped[str] = mapped_column(
        ForeignKey("teller.accounts.id"), primary_key=True
    )
    ledger: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(precision=19, scale=2), nullable=True
    )
    available: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(precision=19, scale=2), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.current_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.current_timestamp(),
        onupdate=func.current_timestamp()
    )

class AccountDetail(Base):
    __tablename__ = "account_details"
    __table_args__ = {"schema": "teller"}

    account_id: Mapped[str] = mapped_column(
        ForeignKey("teller.accounts.id"), primary_key=True
    )
    account_number: Mapped[str] = mapped_column(String(50), nullable=False)
    routing_number_ach: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    routing_number_wire: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    routing_number_bacs: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.current_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.current_timestamp(),
        onupdate=func.current_timestamp()
    )

class TransactionCounterparty(Base):
    __tablename__ = "transaction_counterparties"
    __table_args__ = {"schema": "teller"}

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    type: Mapped[Optional[str]] = mapped_column(
        Enum(CounterpartyType, schema="teller", name="counterparty_type", native_enum=True),
        nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.current_timestamp()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.current_timestamp(),
        onupdate=func.current_timestamp()
    ) 