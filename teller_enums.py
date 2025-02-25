from enum import Enum

## https://teller.io/docs/api

class TellerAccountType(Enum):
    NONE = None
    DEPOSITORY = "depository"
    CREDIT = "credit"

class TellerAccountSubtype(Enum):
    NONE = None
    CHECKING = "checking"
    SAVINGS = "savings" 
    MONEY_MARKET = "money_market"
    CERTIFICATE_OF_DEPOSIT = "certificate_of_deposit"
    TREASURY = "treasury"
    SWEEP = "sweep"
    CREDIT_CARD = "credit_card"

class TellerAccountStatus(Enum):
    NONE = None
    OPEN = "open"
    CLOSED = "closed"

class TellerTransactionDetailsProcessingStatus(Enum):
    NONE = None
    PENDING = "pending"
    COMPLETE = "complete"

class TellerTransactionStatus(Enum):
    NONE = None
    POSTED = "posted"
    PENDING = "pending"

class TellerTransactionDetailsCounterpartyType(Enum):
    NONE = None
    ORGANIZATION = "organization"
    PERSON = "person"

class TellerIdentityType(Enum):
    NONE = None
    ORGANIZATION = "organization"
    PERSON = "person"

class TellerIdentityPhoneNumberType(Enum):  
    NONE = None
    MOBILE = "mobile"
    HOME = "home"
    WORK = "work"
    UNKNOWN = "unknown"

class TellerIdentityNameType(Enum):
    NONE = None
    NAME = "name"
    ALIAS = "alias"

class TellerTransactionDetailsCategory(Enum):
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