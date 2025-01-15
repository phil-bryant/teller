from typing import Optional
from sqlalchemy import String, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.sql import func
from sqlalchemy.dialects.postgresql import JSONB
from datetime import datetime

class Base(DeclarativeBase):
    pass

class Institution(Base):
    __tablename__ = 'institutions'
    __table_args__ = {'schema': 'teller'}
    
    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.current_timestamp())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.current_timestamp())

class Account(Base):
    __tablename__ = 'accounts'
    __table_args__ = {'schema': 'teller'}
    
    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    enrollment_id: Mapped[str] = mapped_column(String(50))
    institution_id: Mapped[str] = mapped_column(ForeignKey('teller.institutions.id'))
    name: Mapped[str] = mapped_column(String(100))
    type: Mapped[str] = mapped_column('account_type')
    subtype: Mapped[str] = mapped_column('account_subtype')
    currency: Mapped[str] = mapped_column(String(3))
    last_four: Mapped[str] = mapped_column(String(4))
    status: Mapped[str] = mapped_column('account_status')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.current_timestamp())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.current_timestamp())

class AccountBalance(Base):
    __tablename__ = 'account_balances'
    __table_args__ = {'schema': 'teller'}
    
    account_id: Mapped[str] = mapped_column(ForeignKey('teller.accounts.id'), primary_key=True)
    ledger: Mapped[Optional[float]] = mapped_column(nullable=True)
    available: Mapped[Optional[float]] = mapped_column(nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.current_timestamp())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.current_timestamp())

class AccountDetail(Base):
    __tablename__ = 'account_details'
    __table_args__ = {'schema': 'teller'}
    
    account_id: Mapped[str] = mapped_column(ForeignKey('teller.accounts.id'), primary_key=True)
    account_number: Mapped[str] = mapped_column(String(50))
    routing_number_ach: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    routing_number_wire: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    routing_number_bacs: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.current_timestamp())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.current_timestamp()) 