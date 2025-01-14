#! /usr/bin/env python3
import json
import requests
from typing import List, Dict
from pathlib import Path
from account import Account

class TellerClient:
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
    
    def _get(self, url: str) -> dict:
        response = requests.get(
            url,
            auth=(self.auth_token, ""),
            cert=self.cert,
            headers=self.headers
        )
        
        if response.status_code != 200:
            raise Exception(f"Failed to fetch data: {response.status_code} {response.text}")
            
        return response.json()
    
    def get_accounts(self) -> List[Account]:
        return [Account(account_data) for account_data in self._get(f"{self.BASE_URL}/accounts")]
    
    def get_account_balances(self, account: Account) -> Dict:
        return self._get(account.balances_link)
    
    def get_account_transactions(self, account: Account) -> List[Dict]:
        return self._get(account.transactions_link)

def main():
    client = TellerClient()
    accounts = client.get_accounts()
    
    for account in accounts:
        print(account)
        balances = client.get_account_balances(account)
        if 'available' in balances:
            print(f"  Available: ${balances['available']}")
        if 'current' in balances:
            print(f"  Current: ${balances['current']}")
        if 'credit' in balances:
            print(f"  Credit: ${balances['credit']}")

if __name__ == "__main__":
    main() 