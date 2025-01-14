#! /usr/bin/env python3
import json
import requests
from typing import List, Dict
from pathlib import Path
from teller_account import TellerAccount

class TellerAPIClient:
    BASE_URL = "https://api.teller.io"

    def __init__(self):
        teller_dir = Path.home() / ".teller"
        with open(teller_dir / "auth_token.json", "r") as f:
            self.auth_token = json.load(f)["current"]
        self.cert = (
            str(teller_dir / "certificate.pem"),
            str(teller_dir / "private_key.pem")
        )
        self.headers = {
            "Accept": "application/json",
            "Content-Type": "application/json"
        }

    def get(self, url: str, params: Dict = None) -> dict:
        response = requests.get(
            url,
            auth=(self.auth_token, ""),
            cert=self.cert,
            headers=self.headers,
            params=params
        )
        if response.status_code != 200:
            raise Exception(f"Failed to fetch data: {response.status_code} {response.text}")
        return response.json()

    def get_accounts(self) -> List[TellerAccount]:
        return [TellerAccount(account_data, self) for account_data in self.get(f"{self.BASE_URL}/accounts")]

def main():
    client = TellerAPIClient()
    accounts = client.get_accounts()
    for account in accounts:
        print(account)
    print(accounts[0].available_balance)
    transactions = accounts[0].get_transactions()
    for transaction in transactions:
        print(transaction)

if __name__ == "__main__":
    main() 
