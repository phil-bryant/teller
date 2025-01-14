#! /usr/bin/env python3
import json
import requests
from typing import List, Dict
from pathlib import Path
from teller_account import TellerAccount

class TellerAPIClient:
    BASE_URL = "https://api.teller.io"
    PAGE_SIZE = 100

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

    def _get(self, url: str, params: Dict = None) -> dict:
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

    def _get_paginated(self, url: str, params: Dict = None) -> List[Dict]:
        all_items = []
        request_params = params.copy() if params else {}
        while True:
            batch = self._get(url, request_params)
            if not batch:
                break
            all_items.extend(batch)
            if len(batch) < self.PAGE_SIZE:
                break
            request_params['from_id'] = batch[-1]['id']
        return all_items

    def get_accounts(self) -> List[TellerAccount]:
        return [TellerAccount(account_data, self) for account_data in self._get(f"{self.BASE_URL}/accounts")]

def main():
    client = TellerAPIClient()
    accounts = client.get_accounts()
    for account in accounts:
        print(account)
    print(accounts[0].available_balance)
    transactions = accounts[0].get_transactions(date_from="2024-01-01")
    for transaction in transactions:
        print(transaction)
    print(len(transactions))
    
if __name__ == "__main__":
    main() 
