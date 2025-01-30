#!/usr/bin/env python3
import json
import requests
from pathlib import Path

def check_disney_transactions():
    # Load auth token
    teller_dir = Path.home() / ".teller"
    with open(teller_dir / "auth_token.json", "r") as f:
        auth_token = json.load(f)["current"]
    
    cert = (str(teller_dir / "certificate.pem"), str(teller_dir / "private_key.pem"))
    base_url = "https://api.teller.io"
    
    # Get all accounts
    response = requests.get(
        f"{base_url}/accounts",
        auth=(auth_token, ""),
        cert=cert,
        verify=True
    )
    accounts = response.json()
    
    # Get all Disney transactions
    for account in accounts:
        response = requests.get(
            f"{base_url}/accounts/{account['id']}/transactions",
            auth=(auth_token, ""),
            cert=cert,
            verify=True
        )
        
        transactions = response.json()
        disney_txns = [t for t in transactions if "disney" in t["description"].lower()]
        
        for t in disney_txns:
            print("\n==================")
            print(f"Transaction: {t['id']}")
            print(f"Description: {t['description']}")
            print("Raw API Response:")
            print(json.dumps(t, indent=2))

if __name__ == "__main__":
    check_disney_transactions() 