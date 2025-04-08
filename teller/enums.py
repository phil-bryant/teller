from enum import Enum, auto
from .enum_ import TellerEnum

## https://teller.io/docs/api

class TellerAccountType(TellerEnum):
    NONE = None
    DEPOSITORY = "depository"
    CREDIT = "credit"

class TellerAccountSubtype(TellerEnum):
    NONE = None
    CHECKING = "checking"
    SAVINGS = "savings" 
    MONEY_MARKET = "money_market"
    CERTIFICATE_OF_DEPOSIT = "certificate_of_deposit"
    TREASURY = "treasury"
    SWEEP = "sweep"
    CREDIT_CARD = "credit_card"

class TellerAccountStatus(TellerEnum):
    NONE = None
    OPEN = "open"
    CLOSED = "closed"

class TellerTransactionDetailsProcessingStatus(TellerEnum):
    NONE = None
    PENDING = "pending"
    COMPLETE = "complete"

class TellerTransactionStatus(TellerEnum):
    NONE = None
    POSTED = "posted"
    PENDING = "pending"

class TellerTransactionDetailsCounterpartyType(TellerEnum):
    NONE = None
    ORGANIZATION = "organization"
    PERSON = "person"

class TellerIdentityType(TellerEnum):
    NONE = None
    ORGANIZATION = "organization"
    PERSON = "person"

class TellerIdentityPhoneNumberType(TellerEnum):  
    NONE = None
    MOBILE = "mobile"
    HOME = "home"
    WORK = "work"
    UNKNOWN = "unknown"

class TellerIdentityNameType(TellerEnum):
    NONE = None
    NAME = "name"
    ALIAS = "alias"

class TellerTransactionDetailsCategory(TellerEnum):
    NONE = None
    ACCOMMODATION = "accommodation"
    ADVERTISING = "advertising"
    BAR = "bar"
    CHARITY = "charity"
    CLOTHING = "clothing"
    DINING = "dining"
    EDUCATION = "education"
    ELECTRONICS = "electronics"
    ENTERTAINMENT = "entertainment"
    FUEL = "fuel"
    GENERAL = "general"
    GROCERIES = "groceries"
    HEALTH = "health"
    HOME = "home"
    INCOME = "income"
    INSURANCE = "insurance"
    INVESTMENT = "investment"
    LOAN = "loan"
    OFFICE = "office"
    PHONE = "phone"
    SERVICE = "service"
    SHOPPING = "shopping"
    SOFTWARE = "software"
    SPORT = "sport"
    TAX = "tax"
    TRANSPORT = "transport"
    TRANSPORTATION = "transportation"
    UTILITIES = "utilities" 