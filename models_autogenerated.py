from peewee import *
from playhouse.postgres_ext import *

database = PostgresqlDatabase('prod', **{'user': 'teller', 'password': 'QkCV#KC*eA9BDRx', 'host': '127.0.0.1', 'port': 5432, 'options': '-c search_path=teller'})

class UnknownField(object):
    def __init__(self, *_, **__): pass

class BaseModel(Model):
    class Meta:
        database = database

class AccountLinks(BaseModel):
    self_link = TextField()
    details = TextField(null=True)
    balances = TextField(null=True)
    transactions = TextField(null=True)
    account_links_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'account_links'
        schema = 'teller'

class Institution(BaseModel):
    institution_id = TextField(primary_key=True)
    name = TextField(unique=True)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'institution'
        schema = 'teller'

class Account(BaseModel):
    currency = CharField()
    enrollment_id = TextField()
    account_id = TextField(primary_key=True)
    institution = ForeignKeyField(column_name='institution_id', field='institution_id', model=Institution)
    last_four = CharField()
    account_links = ForeignKeyField(column_name='account_links_id', field='account_links_id', model=AccountLinks)
    name = TextField(unique=True)
    type = UnknownField()  # USER-DEFINED
    subtype = UnknownField()  # USER-DEFINED
    status = UnknownField()  # USER-DEFINED
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'account'
        schema = 'teller'

class AccountBalancesLinks(BaseModel):
    self_link = TextField(unique=True)
    account_link = TextField(unique=True)
    account_balances_links_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'account_balances_links'
        schema = 'teller'

class AccountBalances(BaseModel):
    account = ForeignKeyField(column_name='account_id', field='account_id', model=Account)
    ledger = DecimalField(null=True)
    account_balances_links = ForeignKeyField(column_name='account_balances_links_id', field='account_balances_links_id', model=AccountBalancesLinks)
    available = DecimalField(null=True)
    account_balances_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'account_balances'
        schema = 'teller'

class AccountDetailsLinks(BaseModel):
    account_details_links_id = BigAutoField()
    self_link = TextField(unique=True)
    account_link = TextField(unique=True)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'account_details_links'
        schema = 'teller'

class RoutingNumbers(BaseModel):
    ach = TextField(null=True, unique=True)
    wire = TextField(null=True, unique=True)
    bacs = TextField(null=True)
    routing_numbers_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'routing_numbers'
        schema = 'teller'

class AccountDetails(BaseModel):
    account = ForeignKeyField(column_name='account_id', field='account_id', model=Account, primary_key=True)
    account_number = TextField(unique=True)
    account_details_links = ForeignKeyField(column_name='account_details_links_id', field='account_details_links_id', model=AccountDetailsLinks, unique=True)
    routing_numbers = ForeignKeyField(column_name='routing_numbers_id', field='routing_numbers_id', model=RoutingNumbers, null=True, unique=True)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'account_details'
        schema = 'teller'

class Identity(BaseModel):
    type = UnknownField()  # USER-DEFINED
    identity_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'identity'
        schema = 'teller'

class AccountIdentities(BaseModel):
    account = ForeignKeyField(column_name='account_id', field='account_id', model=Account)
    identity = ForeignKeyField(column_name='identity_id', field='identity_id', model=Identity)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'account_identities'
        indexes = (
            (('account', 'identity'), True),
        )
        schema = 'teller'
        primary_key = False

class AuditLog(BaseModel):
    id = BigAutoField()
    table_name = TextField()
    record_id = TextField()
    action = TextField()
    old_data = BinaryJSONField(null=True)
    new_data = BinaryJSONField(null=True)
    changed_by = TextField(constraints=[SQL("DEFAULT 'CURRENT_USER'")], null=True)
    changed_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'audit_log'
        schema = 'teller'

class IdentityAddressData(BaseModel):
    street = TextField()
    city = TextField()
    region = TextField()
    country = CharField()
    postal_code = TextField()
    identity_address_data_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'identity_address_data'
        indexes = (
            (('street', 'city', 'region', 'country', 'postal_code'), True),
        )
        schema = 'teller'

class IdentityAddress(BaseModel):
    primary_address = BooleanField(constraints=[SQL("DEFAULT false")])
    identity_address_data = ForeignKeyField(column_name='identity_address_data_id', field='identity_address_data_id', model=IdentityAddressData)
    identity_address_id = BigAutoField()
    identity = ForeignKeyField(column_name='identity_id', field='identity_id', model=Identity)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'identity_address'
        indexes = (
            (('identity_address_data', 'identity'), True),
        )
        schema = 'teller'

class IdentityEmail(BaseModel):
    data = TextField(unique=True)
    identity_email_id = BigAutoField()
    identity = ForeignKeyField(column_name='identity_id', field='identity_id', model=Identity)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'identity_email'
        schema = 'teller'

class IdentityName(BaseModel):
    type = UnknownField()  # USER-DEFINED
    data = TextField()
    identity_name_id = BigAutoField()
    identity = ForeignKeyField(column_name='identity_id', field='identity_id', model=Identity)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'identity_name'
        indexes = (
            (('data', 'identity'), True),
        )
        schema = 'teller'

class IdentityPhoneNumber(BaseModel):
    type = UnknownField()  # USER-DEFINED
    data = TextField()
    identity_phone_number_id = BigAutoField()
    identity = ForeignKeyField(column_name='identity_id', field='identity_id', model=Identity)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'identity_phone_number'
        indexes = (
            (('data', 'identity'), True),
        )
        schema = 'teller'

class TransactionDetailsCounterparty(BaseModel):
    name = TextField()
    type = UnknownField()  # USER-DEFINED
    transaction_details_counterparty_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'transaction_details_counterparty'
        schema = 'teller'

class TransactionDetails(BaseModel):
    processing_status = TextField()
    category = UnknownField(null=True)  # USER-DEFINED
    counterparty = ForeignKeyField(column_name='counterparty_id', field='transaction_details_counterparty_id', model=TransactionDetailsCounterparty, null=True)
    transaction_details_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'transaction_details'
        schema = 'teller'

class TransactionLinks(BaseModel):
    self_link = TextField(unique=True)
    account = TextField(unique=True)
    transaction_links_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'transaction_links'
        schema = 'teller'

class TransactionType(BaseModel):
    code = TextField(unique=True)
    transaction_type_id = BigAutoField()
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'transaction_type'
        schema = 'teller'

class Transaction(BaseModel):
    account = ForeignKeyField(column_name='account_id', field='account_id', model=Account)
    amount = DecimalField()
    date = DateField()
    description = TextField()
    transaction_details = ForeignKeyField(column_name='transaction_details_id', field='transaction_details_id', model=TransactionDetails, unique=True)
    status = UnknownField()  # USER-DEFINED
    transaction_id = TextField(primary_key=True)
    transaction_links = ForeignKeyField(column_name='transaction_links_id', field='transaction_links_id', model=TransactionLinks, unique=True)
    running_balance = DecimalField(null=True)
    transaction_type = ForeignKeyField(column_name='transaction_type_id', field='transaction_type_id', model=TransactionType)
    created_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)
    updated_at = DateTimeField(constraints=[SQL("DEFAULT CURRENT_TIMESTAMP")], null=True)

    class Meta:
        table_name = 'transaction'
        schema = 'teller'

