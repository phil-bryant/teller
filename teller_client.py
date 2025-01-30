#! /usr/bin/env python3
import json
import requests
from typing import List, Dict
from pathlib import Path
from teller_account import TellerAccount
from teller_account_identities import TellerAccountIdentities
from os import getenv
from dotenv import load_dotenv
import argparse
from decimal import Decimal
from datetime import datetime
from teller_object import TellerObject

class TellerAPIClient:
    BASE_URL = "https://api.teller.io"

    def __init__(self):
        env_path = Path.home() / ".env"
        if not env_path.exists():
            raise FileNotFoundError(
                f"Environment file not found at {env_path}. "
                "Please create it with required database credentials."
            )
        load_dotenv(env_path)
        teller_dir = Path.home() / ".teller"
        if not teller_dir.exists():
            raise FileNotFoundError(f"Teller directory not found at {teller_dir}")
        auth_token_file = teller_dir / "auth_token.json"
        if not auth_token_file.exists():
            raise FileNotFoundError(f"Auth token file not found at {auth_token_file}")
        with open(auth_token_file, "r") as f:
            auth_data = json.load(f)
            if "current" not in auth_data:
                raise ValueError("Auth token file is missing 'current' key")
            self.auth_token = auth_data["current"]
        cert_file = teller_dir / "certificate.pem"
        key_file = teller_dir / "private_key.pem"
        if not cert_file.exists():
            raise FileNotFoundError(f"Certificate file not found at {cert_file}")
        if not key_file.exists():
            raise FileNotFoundError(f"Private key file not found at {key_file}")
        self.cert = (str(cert_file), str(key_file))
        for file in [cert_file, key_file]:
            if file.stat().st_mode & 0o777 != 0o600:
                print(f"Warning: {file} should have 600 permissions for security")
        self.headers = {
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
        TellerObject.set_api_client(self)

    def get(self, url: str, params: Dict = None) -> dict:
        try:
            print(f"Attempting to connect to {url}")
            print(f"Using cert files: {self.cert}")
            print(f"Auth token: {self.auth_token[:5]}...")
            response = requests.get(
                url,
                auth=(self.auth_token, ""),
                cert=self.cert,
                headers=self.headers,
                params=params,
                verify=True
            )
            if response.status_code != 200:
                raise Exception(f"Failed to fetch data: {response.status_code} {response.text}")
            return response.json()
        except requests.exceptions.SSLError as e:
            print(f"SSL Error: {e}")
            raise
        except requests.exceptions.ConnectionError as e:
            print(f"Connection Error: {e}")
            for cert_file in self.cert:
                if not Path(cert_file).exists():
                    print(f"Certificate file missing: {cert_file}")
                else:
                    print(f"Certificate file exists: {cert_file}")
            raise

    def get_account_identities(self) -> list[TellerAccountIdentities]:
        return [TellerAccountIdentities(account_data) for account_data in self.get(f"{self.BASE_URL}/identity")]

def main():
    parser = argparse.ArgumentParser(description='Teller API Client')
    args = parser.parse_args()
    client = TellerAPIClient()
    account_identities = client.get_account_identities()
    for account_identity in account_identities:
        print(account_identity)

if __name__ == "__main__":
    main() 