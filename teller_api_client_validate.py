#!/usr/bin/env python3

import datetime
import os
import sys
from decimal import Decimal
from enum import Enum
from typing import List, Optional

from object_inspector import save_snapshot
from teller_account import TellerAccount, TellerAccountBalances, TellerAccountDetails, TellerAccountLinks, TellerAccountStatus, TellerAccountSubtype, TellerAccountType
from teller_account_identities import TellerAccountIdentities
from teller_api_client import TellerAPIClient
from teller_institution import TellerInstitution
from teller_transaction import TellerTransaction
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_links import TellerTransactionLinks
from teller_transaction_type import TellerTransactionType

from teller_identity import TellerIdentity, TellerIdentityAddress, TellerIdentityEmail, TellerIdentityName, TellerIdentityPhoneNumber, TellerIdentityType


def main() -> int:
    # Create a mock API client with fixed data
    api_client = TellerAPIClient()
    api_client.base_url = "https://api.teller.io"
    api_client.auth_tuple = ("token_id", "token_secret")
    api_client.cert_pk_tuple = ("token_key", "token_secret")
    
    objects_to_save = []

    # Create account identities using the same pattern as the original client
    account_identities = TellerAccountIdentities(api_client)
    for account_identity in account_identities:
        print(account_identity.account)
        objects_to_save.append(account_identity.account)
        
        # Create transactions for each account
        transactions = []
        for i in range(2):
            # Create transaction details
            details_data = {
                "processing_status": "complete",
                "category": "shopping"
                # Note: no counterparty, which is fine - should blow up if the API has this problem
            }
            
            # Create links data as it would come from the API
            links_data = {
                "account": f"accounts/{account_identity.account.id}",
                "self": f"accounts/{account_identity.account.id}/transactions/txn_p7th7frev0lbhrg1sa{i:03d}"
            }
            
            # Create transaction type data as it would come from the API
            type_data = {
                "category": "outflow" if i == 0 else "inflow",
                "code": "card_payment" if i == 0 else "transfer"
            }
            
            # Create transaction data as a simple dict to match API response format
            transaction_data = {
                "account_id": account_identity.account.id,
                "amount": str(Decimal("-24.71")),
                "date": datetime.date(2024, 5, 28).isoformat(),
                "description": "PAYPAL INST XFER EBAY V2_EFB7260 WEB ID: PAYPALSI77",
                "details": details_data,
                "status": "posted",
                "id": f"txn_p7th7frev0lbhrg1sa{i:03d}",
                "links": links_data,
                "running_balance": "59.87" if i == 0 else "84.58",
                "type": type_data
            }
            transaction = TellerTransaction(transaction_data)
            transactions.append(transaction)
        
        for transaction in transactions:
            print(transaction)
            objects_to_save.append(transaction)
            
        print(account_identity.owners[0])
        objects_to_save.append(account_identity.owners[0])

    # Save objects to a new file
    save_snapshot(objects_to_save, 'new_objects_snapshot.pickle')
    
    return 0


if __name__ == "__main__":
    sys.exit(main()) 