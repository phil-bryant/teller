#! /usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path
from typing import Dict
import requests
import structlog
from dotenv import load_dotenv
from teller_object import TellerObject
from teller_account_identities import TellerAccountIdentities

log = structlog.get_logger()

class TellerAPIError(Exception):
    def __init__(self, message: str, code: str = "", status_code: int = 0):
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code

class TellerAPIClient:
    BASE_URL = "https://api.teller.io"

    def __init__(self):
        load_dotenv(Path.home() / ".env")
        self.kwargs = {
            'auth': (json.load(open(Path.home() / ".teller/auth_token.json"))["current"], ""),
            'cert': (str(Path.home() / ".teller/certificate.pem"), str(Path.home() / ".teller/private_key.pem")),
            'headers': {"Accept": "application/json", "Content-Type": "application/json"},
            'verify': True
        }
        TellerObject.set_api_client(self)

    def get(self, url: str, params: Dict = None) -> dict:
        log.info("Connecting to Teller API", url=url, cert=self.kwargs['cert'], auth_token=self.kwargs['auth'][0][:5])
        response = requests.get(url, params=params, **self.kwargs)
        if response.status_code != 200:
            try:
                payload = response.json()
                err = payload.get("error", {})
                message = err.get("message", response.text)
                code = err.get("code", "")
            except ValueError:
                message = response.text
                code = ""
            raise TellerAPIError(message=message, code=code, status_code=response.status_code)
        return response.json()

    def get_account_identities(self) -> list[TellerAccountIdentities]:
        return [TellerAccountIdentities(account_data) for account_data in self.get(f"{self.BASE_URL}/identity")]

def main():
    args = argparse.ArgumentParser(description='Teller API Client').parse_args()
    try:
        for account_identity in TellerAPIClient().get_account_identities():
            account = account_identity.account
            ## we cannot call account.get_details() yet because we first have to go through the microdeposit verification flow.
            print(account)
            for transaction in account.get_transactions(3):
                print(transaction)
                print(transaction.type)
            for owner in account_identity.owners:
                print(owner)
    except TellerAPIError as exc:
        if exc.code.startswith("enrollment.disconnected"):
            print(f"Teller enrollment requires user action: {exc.code}")
            print("Run ./06_capture_teller_token.sh to reconnect via Teller Connect and refresh token.")
            sys.exit(1)
        print(f"Teller API request failed ({exc.status_code}): {exc.message}")
        if exc.code:
            print(f"Error code: {exc.code}")
        sys.exit(1)

if __name__ == "__main__":
    main() 