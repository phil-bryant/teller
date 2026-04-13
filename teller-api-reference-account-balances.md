# Account Balances (https://teller.io/docs/api/account/balances)

The account balances API provides your application with live, real-time account
balances. At least one balance (ledger or available) is always provided.

## Properties

-   `account_id` _(string)_ - The id of the account the account balances belong to.

-   `ledger` _(string (nullable))_ - The account's ledger balance. The ledger balance is the total amount of funds in the account.

-   `available` _(string (nullable))_ - The account's available balance. The available balance is the ledger balance net any pending inflows or outflows.

-   `links` _(object)_ - An object containing links to related resources. A link indicates the enrollment supports that type of resource. Not every institution implements all of the capabilities that Teller supports. Your application should reflect on the contents of this object to determine what is supported by the financial institution.
    -   `self` _(string)_ - A self link to the account balances.
    -   `account` _(string)_ - A link to the account that owns the balances.

***

## Get Account Balances

Returns the account's balances.

```bash
curl https://api.teller.io/accounts/acc_oiin624iajrg2mp2ea000/balances \
  -u test_token_ky6igyqi3qxa4:
```

```json
{
  "ledger" : "28575.02",
  "links" : {
      "account" : "https://api.teller.io/accounts/acc_oiin624iajrg2mp2ea000",
      "self" : "https://api.teller.io/accounts/acc_oiin624iajrg2mp2ea000/balances"
  },
  "account_id" : "acc_oiin624iajrg2mp2ea000",
  "available" : "28575.02"
}
```
