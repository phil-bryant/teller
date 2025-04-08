#! /usr/bin/env python3
from typing import Optional
from .api_client_type import TellerAPIClient
from .api.api import API
import json
from pathlib import Path
from .account_identities import TellerAccountIdentities
import requests

class TellerAPIClient(TellerAPIClient):
    base_url = "https://api.teller.io"
    auth_tuple = (json.load(open(Path.home() / ".teller/auth_token.json"))["current"], "")
    cert_pk_tuple = (str(Path.home() / ".teller/certificate.pem"), str(Path.home() / ".teller/private_key.pem"))

    @classmethod
    def main(cls):
        accountIdentities = TellerAccountIdentities(cls())
        for account_identity in accountIdentities:
            account_identity.get_transactions(limit=2)
            ## not ready to do this just yet account_identity.save()

    def __init__(self):
        self.api = API(self.base_url, self.auth_tuple, self.cert_pk_tuple)

    def request(self, method, path, params: dict = None) -> dict:
        response = self.api.request(method, path, params)
        if response.status_code != 200: raise Exception(response)
        return response.json()
    
    def get(self, path, params: dict = None) -> dict:
        return self.request("GET", path, params)

if __name__ == "__main__":
    TellerAPIClient.main() 