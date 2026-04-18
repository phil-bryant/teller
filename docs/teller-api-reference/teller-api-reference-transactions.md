# Transactions (https://teller.io/docs/api/account/transactions)

The transactions API exposes the ledger transactions of a financial account.

> **Note**
>
> The initial call to the transactions API can sometimes time out with accounts that have an abnormally large number of transactions. Should this happen wait a few seconds and try again.

## Properties

-   `account_id` _(string)_ - The id of the account that the transaction belongs to.

-   `amount` _(string)_ - The signed amount of the transaction as a string.

-   `date` _(string)_ - The ISO 8601 date of the transaction.

-   `description` _(string)_ - The unprocessed transaction description as it appears on the bank statement.

-   `details` _(object)_ - An object containing additional information regarding the transaction added by Teller's transaction enrichment.
    -   `processing_status` _(string)_ - Indicates the transaction enrichment processing status. Either `pending` or `complete`.
    -   `category` _(string (nullable))_ - The category that the transaction belongs to. Teller uses the following values for categorization: `accommodation`, `advertising`, `bar`, `charity`, `clothing`, `dining`, `education`, `electronics`, `entertainment`, `fuel`, `general`, `groceries`, `health`, `home`, `income`, `insurance`, `investment`, `loan`, `office`, `phone`, `service`, `shopping`, `software`, `sport`, `tax`, `transport`, `transportation`, and `utilities`.
    -   `counterparty` _(object)_ - An object containing information regarding the transaction's recipient
        -   `name` _(string (nullable))_ - The processed counterparty name.
        -   `type` _(string (nullable))_ - The counterparty type: `organization` or `person`.

-   `status` _(string)_ - The transaction's status: `posted` or `pending`.

-   `id` _(string)_ - The id of the transaction itself.

-   `links` _(object)_ - An object containing links to related resources. A link indicates the enrollment supports that type of resource. Not every institution implements all of the capabilities that Teller supports. Your application should reflect on the contents of this object to determine what is supported by the financial institution.
    -   `self` _(string)_ - A self link to the transaction.
    -   `account` _(string)_ - A link to the account that the transaction belongs to.

-   `running_balance` _(string (nullable))_ - The running balance of the account that the transaction belongs to. Running balance is only present on transactions with a `posted` status.

-   `type` _(string)_ - The type code transaction, e.g. `card_payment`.

***

## List Transactions

Returns a list of all transactions belonging to the account.

### Pagination

The Transactions endpoint returns all transactions for the given account. Usually this does not represent a large amount of data transfer, but if your application has specific requirements of minimizing the amount of data going over the wire the transactions list endpoint supports pagination controls.

Pagination controls are given as query params on the request URL.

-   `count` _(integer)_ - The maximum number of transactions to return in the API response.

-   `from_id` _(string)_ - Paginate backward from this transaction. Returns transactions older than the one with this ID. For recent activity, use date ranges or webhooks.

-   `start_date` _(string)_ - Filter transactions to include only those on or after this date (inclusive). Must be in ISO 8601 format, for example 2025-01-01.

-   `end_date` _(string)_ - Filter transactions to include only those on or before this date (inclusive). Must be in ISO 8601 format, for example 2025-01-31.

```bash
curl https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions \
  -u test_token_ky6igyqi3qxa4:
```

```json
[
  {
    "details" : {
      "processing_status" : "complete",
      "category" : "general",
      "counterparty" : {
          "name" : "YOURSELF",
          "type" : "person"
      }
    },
    "running_balance" : null,
    "description" : "Transfer to Checking",
    "id" : "txn_oiluj93igokseo0i3a000",
    "date" : "2023-07-15",
    "account_id" : "acc_oiin624kqjrg2mp2ea000",
    "links" : {
      "account" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000",
      "self" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions/txn_oiluj93igokseo0i3a000"
    },
    "amount" : "86.46",
    "type" : "transfer",
    "status" : "pending"
  },
  ...
]
```

***

## Get Transaction

Returns an individual transaction.

```bash
curl https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions/txn_oiluj93igokseo0i3a005 \
  -u test_token_ky6igyqi3qxa4:
```

```json
{
  "running_balance" : null,
  "details" : {
     "category" : "service",
     "counterparty" : {
        "type" : "organization",
        "name" : "CARDTRONICS"
     },
     "processing_status" : "complete"
  },
  "description" : "ATM Withdrawal",
  "account_id" : "acc_oiin624kqjrg2mp2ea000",
  "date" : "2023-07-13",
  "id" : "txn_oiluj93igokseo0i3a005",
  "links" : {
     "account" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000",
     "self" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions/txn_oiluj93igokseo0i3a005"
  },
  "amount" : "42.47",
  "type" : "atm",
  "status" : "posted"
},
```

***

## Syncing Transactions

Use these patterns to fetch only new transactions without re-downloading your full history.

### Using date ranges

Use `start_date` and `end_date` to bound your sync window; both dates are inclusive. Expand the window 7-10 days beyond your last sync to capture transactions that shift dates when moving from `pending` to `posted`.

When a pending transaction posts, its date often changes to the posting date. If you only query from your last sync date forward, you may miss these transactions.

```bash
curl -G "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions" \
  -d "start_date=2025-01-01" \
  -d "end_date=2025-01-31" \
  -u test_token_ky6igyqi3qxa4:
```

Your expanded window will return transactions you've already stored. Reconcile by matching on transaction ID: insert new records and update existing ones. If the date range returns more than `count` transactions, use `from_id` to paginate through the rest of the window.

> **Note**
>
> Teller maintains stable transaction IDs. Occasionally, when a pending transaction changes significantly upon posting and cannot be matched to the original, it's created as a new record with a new ID. Account for this in your reconciliation.

### Using webhooks

Subscribe to [`transactions.processed`](/docs/api/webhooks) to receive notifications when new transactions are available. Teller refreshes your enrollments at least once per day. When new transactions are found, this webhook fires, and you call the transactions API to retrieve them.
