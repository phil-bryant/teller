#! /usr/bin/env python3
import json
import requests
from typing import List, Dict
from pathlib import Path
from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import Session, sessionmaker
from models import (
    Base, Institution, Account, AccountBalance, AccountDetail,
    AccountType, AccountSubtype, AccountStatus,
    Transaction, TransactionCounterparty,
    TransactionStatus, ProcessingStatus, CounterpartyType,
    AccountLinks, TransactionLinks
)
from teller_account import TellerAccount
from os import getenv
from dotenv import load_dotenv
import argparse
from decimal import Decimal

class TellerAPIClient:
    BASE_URL = "https://api.teller.io"
    
    def __init__(self):
        # Use ~/.env instead of ~/.teller/.env
        env_path = Path.home() / ".env"
        if not env_path.exists():
            raise FileNotFoundError(
                f"Environment file not found at {env_path}. "
                "Please create it with required database credentials."
            )
        load_dotenv(env_path)
        
        # Still look for auth files in ~/.teller
        teller_dir = Path.home() / ".teller"
        
        # Verify teller directory exists
        if not teller_dir.exists():
            raise FileNotFoundError(f"Teller directory not found at {teller_dir}")
        
        # Verify auth token file
        auth_token_file = teller_dir / "auth_token.json"
        if not auth_token_file.exists():
            raise FileNotFoundError(f"Auth token file not found at {auth_token_file}")
        
        with open(auth_token_file, "r") as f:
            auth_data = json.load(f)
            if "current" not in auth_data:
                raise ValueError("Auth token file is missing 'current' key")
            self.auth_token = auth_data["current"]
        
        # Verify certificate files
        cert_file = teller_dir / "certificate.pem"
        key_file = teller_dir / "private_key.pem"
        
        if not cert_file.exists():
            raise FileNotFoundError(f"Certificate file not found at {cert_file}")
        if not key_file.exists():
            raise FileNotFoundError(f"Private key file not found at {key_file}")
        
        self.cert = (str(cert_file), str(key_file))
        
        # Verify file permissions
        for file in [cert_file, key_file]:
            if file.stat().st_mode & 0o777 != 0o600:
                print(f"Warning: {file} should have 600 permissions for security")
        
        self.headers = {
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
        required_env_vars = [
            'POSTGRES_USER',
            'POSTGRES_PASSWORD', 
            'POSTGRES_HOST',
            'POSTGRES_PORT',
            'POSTGRES_DB'
        ]
        
        missing_vars = [var for var in required_env_vars if not getenv(var)]
        if missing_vars:
            raise EnvironmentError(
                f"Missing required environment variables: {', '.join(missing_vars)}"
            )
        
        # Debug: Print all environment variables (with password masked)
        print("Database connection parameters:")
        print(f"Host: {getenv('POSTGRES_HOST')}")
        print(f"Port: {getenv('POSTGRES_PORT')}")
        print(f"Database: {getenv('POSTGRES_DB')}")
        print(f"User: {getenv('POSTGRES_USER')}")        
        # Construct database URL with proper psycopg3 format
        db_url = (
            f"postgresql+psycopg://"  # Add back +psycopg to specify psycopg3 driver
            f"{getenv('POSTGRES_USER')}:{getenv('POSTGRES_PASSWORD')}@"
            f"{getenv('POSTGRES_HOST')}:{getenv('POSTGRES_PORT')}"
            f"/{getenv('POSTGRES_DB')}"
        )
        
        # Add debug output
        print(f"Connecting to database with URL: {db_url.replace(getenv('POSTGRES_PASSWORD'), '****')}")
        
        self.engine = create_engine(
            db_url,
            connect_args={"application_name": "teller_sync"},
            future=True  # Enable SQLAlchemy 2.0 behavior
        )
        self.Session = Session

    def sync_institution(self, session: Session, institution_data: dict) -> Institution:
        stmt = select(Institution).where(Institution.id == institution_data["id"])
        institution = session.execute(stmt).scalar_one_or_none()
        if not institution:
            institution = Institution(
                id=institution_data["id"],
                name=institution_data["name"]
            )
            session.add(institution)
        return institution

    def sync_account(self, session: Session, account_data: dict) -> Account:
        stmt = select(Account).where(Account.id == account_data["id"])
        account = session.execute(stmt).scalar_one_or_none()
        if not account:
            account = Account(
                id=account_data["id"],
                enrollment_id=account_data["enrollment_id"],
                institution_id=account_data["institution"]["id"],
                name=account_data["name"],
                type=AccountType[account_data["type"]],
                subtype=AccountSubtype[account_data["subtype"]],
                currency=account_data["currency"],
                last_four=account_data["last_four"],
                status=AccountStatus[account_data["status"]]
            )
            session.add(account)
        
        # Add this: Sync the links
        self.sync_account_links(session, account.id, account_data["links"])
        
        return account

    def sync_account_balance(self, session: Session, account_id: str, balance_data: dict):
        stmt = select(AccountBalance).where(AccountBalance.account_id == account_id)
        balance = session.execute(stmt).scalar_one_or_none()
        if not balance:
            balance = AccountBalance(
                account_id=account_id,
                ledger=Decimal(balance_data.get("ledger", "0")) if balance_data.get("ledger") else None,
                available=Decimal(balance_data.get("available", "0")) if balance_data.get("available") else None
            )
            session.add(balance)
        else:
            balance.ledger = Decimal(balance_data.get("ledger", "0")) if balance_data.get("ledger") else None
            balance.available = Decimal(balance_data.get("available", "0")) if balance_data.get("available") else None
        return balance

    def sync_account_details(self, session: Session, account_id: str, details_data: dict):
        stmt = select(AccountDetail).where(AccountDetail.account_id == account_id)
        details = session.execute(stmt).scalar_one_or_none()
        if not details:
            details = AccountDetail(
                account_id=account_id,
                account_number=details_data["account_number"],
                routing_number_ach=details_data.get("routing_numbers", {}).get("ach"),
                routing_number_wire=details_data.get("routing_numbers", {}).get("wire"),
                routing_number_bacs=details_data.get("routing_numbers", {}).get("bacs")
            )
            session.add(details)
        return details

    def sync_account_links(self, session: Session, account_id: str, links_data: dict):
        stmt = select(AccountLinks).where(AccountLinks.account_id == account_id)
        links = session.execute(stmt).scalar_one_or_none()
        if not links:
            links = AccountLinks(
                account_id=account_id,
                self_link=links_data["self"],
                balances_link=links_data.get("balances"),
                transactions_link=links_data.get("transactions"),
                details_link=links_data.get("details")
            )
            session.add(links)
        return links

    def sync_transaction(self, session: Session, account_id: str, transaction_data: dict):
        stmt = select(Transaction).where(Transaction.id == transaction_data["id"])
        transaction = session.execute(stmt).scalar_one_or_none()
        
        # Add debug prints for counterparty data
        print("\n=== Transaction Counterparty Debug ===")
        print(f"Transaction ID: {transaction_data['id']}")
        print(f"Description: {transaction_data['description']}")
        print("Raw transaction details:", json.dumps(transaction_data.get('details', {}), indent=2))
        
        # Sync counterparty first if it exists
        counterparty_id = None
        if "counterparty" in transaction_data.get("details", {}) and transaction_data["details"]["counterparty"]:
            counterparty_data = transaction_data["details"]["counterparty"]
            print("Found counterparty data:", json.dumps(counterparty_data, indent=2))
            counterparty = self.sync_counterparty(session, counterparty_data)
            counterparty_id = counterparty.id

        if not transaction:
            transaction = Transaction(
                id=transaction_data["id"],
                account_id=account_id,
                amount=Decimal(transaction_data["amount"]),
                date=transaction_data["date"],
                description=transaction_data["description"],
                status=TransactionStatus[transaction_data["status"]],
                processing_status=ProcessingStatus[transaction_data["details"]["processing_status"]],
                category=transaction_data.get("details", {}).get("category"),
                counterparty_id=counterparty_id,
                running_balance=Decimal(transaction_data["running_balance"]) if transaction_data.get("running_balance") else None,
                type=transaction_data["type"]
            )
            session.add(transaction)
        
        # Add this: Sync the transaction links
        self.sync_transaction_links(session, transaction.id, transaction_data["links"])
        
        return transaction

    def sync_transaction_links(self, session: Session, transaction_id: str, links_data: dict):
        stmt = select(TransactionLinks).where(TransactionLinks.transaction_id == transaction_id)
        links = session.execute(stmt).scalar_one_or_none()
        if not links:
            links = TransactionLinks(
                transaction_id=transaction_id,
                self_link=links_data["self"],
                account_link=links_data["account"]
            )
            session.add(links)
        return links

    def sync_counterparty(self, session: Session, counterparty_data: dict) -> TransactionCounterparty:
        print("\n=== Syncing Counterparty ===")
        print("Input counterparty data:", json.dumps(counterparty_data, indent=2))
        
        # Create new counterparty if name and type combination doesn't exist
        stmt = select(TransactionCounterparty).where(
            TransactionCounterparty.name == counterparty_data["name"],
            TransactionCounterparty.type == counterparty_data["type"]
        )
        counterparty = session.execute(stmt).scalar_one_or_none()
        
        if not counterparty:
            print(f"Creating new counterparty: {counterparty_data['name']} ({counterparty_data.get('type')})")
            counterparty = TransactionCounterparty(
                name=counterparty_data["name"],
                type=CounterpartyType[counterparty_data["type"]] if counterparty_data.get("type") else None
            )
            session.add(counterparty)
        else:
            print(f"Found existing counterparty: {counterparty.name} ({counterparty.type})")
        
        return counterparty

    def sync_all(self):
        # Create tables if they don't exist
        Base.metadata.create_all(self.engine)
        
        # Use explicit transaction management
        with self.engine.begin() as conn:
            with Session(conn) as session:
                accounts_data = self.get(f"{self.BASE_URL}/accounts")
                for account_data in accounts_data:
                    self.sync_institution(session, account_data["institution"])
                    account = self.sync_account(session, account_data)
                    
                    if "balances" in account_data["links"]:
                        balance_data = self.get(account_data["links"]["balances"])
                        self.sync_account_balance(session, account.id, balance_data)
                    
                    if "details" in account_data["links"]:
                        details_data = self.get(account_data["links"]["details"])
                        self.sync_account_details(session, account.id, details_data)
                    
                    # Add transactions sync
                    if "transactions" in account_data["links"]:
                        transactions_data = self.get(account_data["links"]["transactions"])
                        for transaction_data in transactions_data:
                            self.sync_transaction(session, account.id, transaction_data)
                
                # No need for explicit commit - handled by context manager

    def get(self, url: str, params: Dict = None) -> dict:
        try:
            print(f"Attempting to connect to {url}")
            print(f"Using cert files: {self.cert}")
            print(f"Auth token: {self.auth_token[:5]}...")  # Only show first 5 chars for security
            
            response = requests.get(
                url,
                auth=(self.auth_token, ""),
                cert=self.cert,
                headers=self.headers,
                params=params,
                verify=True  # Explicitly enable SSL verification
            )
            
            if response.status_code != 200:
                raise Exception(f"Failed to fetch data: {response.status_code} {response.text}")
            return response.json()
        except requests.exceptions.SSLError as e:
            print(f"SSL Error: {e}")
            raise
        except requests.exceptions.ConnectionError as e:
            print(f"Connection Error: {e}")
            # Check if cert files exist and are readable
            for cert_file in self.cert:
                if not Path(cert_file).exists():
                    print(f"Certificate file missing: {cert_file}")
                else:
                    print(f"Certificate file exists: {cert_file}")
            raise

    def get_accounts(self) -> List[TellerAccount]:
        return [TellerAccount(account_data, self) for account_data in self.get(f"{self.BASE_URL}/accounts")]

def test_sql_connection():
    print("\n=== Database Connection Test ===")
    
    env_path = Path.home() / ".env"
    load_dotenv(env_path)
    
    host = getenv('POSTGRES_HOST')
    port = getenv('POSTGRES_PORT')
    db = getenv('POSTGRES_DB')
    user = getenv('POSTGRES_USER')
    password = getenv('POSTGRES_PASSWORD')
    
    print("\nActual connection parameters:")
    print(f"Host: '{host}'")
    print(f"Port: '{port}'")
    print(f"Database: '{db}'")
    print(f"User: '{user}'")
    
    db_url = f"postgresql+psycopg://{user}:{password}@{host}:{port}/{db}"
    print(f"\nFull connection URL: {db_url}")
    
    engine = create_engine(db_url, echo=True, future=True)
    
    try:
        with engine.connect() as conn:
            result = conn.execute(text("SELECT 1")).scalar()
            print("\n✅ Successfully connected to database!")
    except Exception as e:
        print(f"\n❌ Connection failed: {str(e)}")
        raise

def main():
    parser = argparse.ArgumentParser(description='Teller API Client')
    parser.add_argument('--test-sql', action='store_true', help='Test SQL connection and exit')
    args = parser.parse_args()
    
    if args.test_sql:
        test_sql_connection()
    else:
        client = TellerAPIClient()
        client.sync_all()

if __name__ == "__main__":
    main() 
