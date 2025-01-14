#! /usr/bin/env python3
from dataclasses import dataclass
import json
import requests
from typing import List
from pathlib import Path

@dataclass
class TellerAccount:
    id: str
    enrollment_id: str
    institution: dict
    name: str
    type: str
    subtype: str
    currency: str
    last_four: str
    status: str
    links: dict

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
    
    def get_accounts(self) -> List[TellerAccount]:
        response = requests.get(
            f"{self.BASE_URL}/accounts",
            auth=(self.auth_token, ""),
            cert=self.cert,
            headers=self.headers
        )
        
        if response.status_code != 200:
            raise Exception(f"Failed to fetch accounts: {response.status_code} {response.text}")
            
        accounts = []
        for account_data in response.json():
            accounts.append(TellerAccount(
                id=account_data["id"],
                enrollment_id=account_data["enrollment_id"], 
                institution=account_data["institution"],
                name=account_data["name"],
                type=account_data["type"],
                subtype=account_data["subtype"],
                currency=account_data["currency"],
                last_four=account_data["last_four"],
                status=account_data["status"],
                links=account_data["links"]
            ))
            
        return accounts

def main():
    client = TellerClient()
    accounts = client.get_accounts()
    
    for account in accounts:
        print(f"\nAccount: {account.name}")
        print(f"Type: {account.type} ({account.subtype})")
        print(f"Last four: {account.last_four}")
        print(f"Institution: {account.institution['name']}")
        print(f"Status: {account.status}")

if __name__ == "__main__":
    main() 