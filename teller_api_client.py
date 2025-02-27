#! /usr/bin/env python3
from teller_api_client_type import TellerAPIClient
from api import API
import json
from pathlib import Path
from teller_account_identities import TellerAccountIdentities
from teller_transaction_type import TellerTransactionType

class TellerAPIClient(TellerAPIClient):
    base_url = "https://api.teller.io"
    auth_tuple = (json.load(open(Path.home() / ".teller/auth_token.json"))["current"], "")
    cert_pk_tuple = (str(Path.home() / ".teller/certificate.pem"), str(Path.home() / ".teller/private_key.pem"))

    def __init__(self):
        self.api = API(self.base_url, self.auth_tuple, self.cert_pk_tuple)
        self.foo = "bar"

    def request(self, method, path, params: dict = None) -> dict:
        response = self.api.request(method, path, params)
        if response.status_code != 200: raise Exception(response)
        return response.json()
    
    def get(self, path, params: dict = None) -> dict:
        return self.request("GET", path, params)

def main():
    api_client = TellerAPIClient()
    transaction_type = TellerTransactionType("ach")
    print(transaction_type)
    accountIdentities = TellerAccountIdentities(TellerAPIClient())
    for account_identity in accountIdentities:
        account = account_identity.account
        ## we cannot call account.get_details() yet because we first have to go through the microdeposit verification flow.
        print(account)
        for transaction in account.get_transactions(2):
            print(transaction)
        for owner in account_identity.owners:
            print(owner)

if __name__ == "__main__":
    main() 