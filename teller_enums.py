from enum import Enum, auto

class TellerAccountType(Enum):
    DEPOSITORY = "depository"
    CREDIT = "credit"

class TellerAccountSubtype(Enum):
    CHECKING = "checking"
    SAVINGS = "savings" 
    MONEY_MARKET = "money_market"
    CERTIFICATE_OF_DEPOSIT = "certificate_of_deposit"
    TREASURY = "treasury"
    SWEEP = "sweep"
    CREDIT_CARD = "credit_card"

class TellerAccountStatus(Enum):
    OPEN = "open"
    CLOSED = "closed"

class TellerTransactionDetailsProcessingStatus(Enum):
    PENDING = "pending"
    COMPLETE = "complete"

class TellerTransactionStatus(Enum):
    POSTED = "posted"
    PENDING = "pending"

class TellerTransactionDetailsCounterpartyType(Enum):
    ORGANIZATION = "organization"
    PERSON = "person"

class TellerIdentityType(Enum):
    ORGANIZATION = "organization"
    PERSON = "person"

class TellerPhoneType(Enum):
    MOBILE = "mobile"
    HOME = "home"
    WORK = "work"
    UNKNOWN = "unknown"

class TellerNameType(Enum):
    NAME = "name"
    ALIAS = "alias"

class TellerTransactionDetailsCategory(Enum):
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