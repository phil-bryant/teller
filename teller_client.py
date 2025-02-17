#! /usr/bin/env python3
from api import API
import json
from pathlib import Path
from teller_account_identities import TellerAccountIdentities

class TellerAPIClient:
    base_url = "https://api.teller.io"
    auth_token = json.load(open(Path.home() / ".teller/auth_token.json"))["current"]
    cert_pk_tuple = (str(Path.home() / ".teller/certificate.pem"), str(Path.home() / ".teller/private_key.pem"))

    def __init__(self):
        self.api = API(self.base_url, self.auth_token, self.cert_pk_tuple)

    def request(self, method, path, params: dict = None) -> json:
        response = self.api.request(method, path, params)
        if response.status_code != 200: raise Exception(response)
        return response.json()
    
    def get(self, path, params: dict = None) -> json:
        return self.request("GET", path, params)

def main():
    for account_identity in TellerAccountIdentities(TellerAPIClient()):
        account = account_identity.account
        ## we cannot call account.get_details() yet because we first have to go through the microdeposit verification flow.
        print(account)
        for transaction in account.get_transactions(2):
            print(transaction)
        for owner in account_identity.owners:
            print(owner)

if __name__ == "__main__":
    main() 