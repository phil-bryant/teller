# Accounts (https://teller.io/docs/api/accounts)

An Account represents an end-user's individual financial account at a given financial institution.

## Properties

-   `currency` _(string)_ - The ISO 4217 currency code of the account.

-   `enrollment_id` _(string)_ - The id of the enrollment that the account belongs to.

-   `id` _(object)_ - The id of the account itself.

-   `institution` _(object)_ - An object containing information about the financial institution that holds the account.
    -   `id` _(string)_ - The internal Teller id assigned to the financial institution.
    -   `name` _(string)_ - The name of the financial institution that holds the account.

-   `last_four` _(string)_ - The last four digits of the account number.

-   `links` _(object)_ - An object containing links to related resources. A link indicates the enrollment supports that type of resource. Not every institution implements all of the capabilities that Teller supports. Your application should reflect on the contents of this object to determine what is supported by the financial institution.
    -   `self` _(string)_ - A self link to the account.
    -   `details` _(string)_ - A link to the account's details, such as account number and routing numbers.
    -   `balances` _(string)_ - A link to the account's live balances.
    -   `transactions` _(string)_ - A link to the account's transactions.

-   `name` _(string)_ - The account's name.

-   `type` _(string)_ - The type of account. Either `depository` or `credit`.

-   `subtype` _(string)_ - The account's subtype.

    depository:
    checking, savings, money_market, certificate_of_deposit, treasury, sweep
    credit:
    credit_card

-   `status` _(string)_ - The account's status: `open` or `closed`. When \`closed it means that it's closed from Teller's perspective, i.e. Teller can still access live enrollment data from the institution, but the account itself is closed, Teller can no longer see that account, or the account transitioned to an insufficient-access state.

    When you try to request an account or any of its sub-resources, and that account is `closed`, Teller returns a 410 response with `account.closed` error. You should parse the error as a dot-separated string where the first token is account.closed and the subsequent tokens, if present, include the reason for closing.

***

## List Accounts

Returns a list of all accounts the end-user granted access to during enrollment in Teller Connect.

```bash
curl https://api.teller.io/accounts \
  -u test_token_ky6igyqi3qxa4:
```

```json
[
  {
      "enrollment_id" : "enr_oiin624rqaojse22oe000",
      "links" : {
        "balances" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/balances",
        "self" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000",
        "transactions" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions"
      },
      "institution" : {
        "name" : "Security Credit Union",
        "id" : "security_cu"
      },
      "type" : "credit",
      "name" : "Platinum Card",
      "subtype" : "credit_card",
      "currency" : "USD",
      "id" : "acc_oiin624kqjrg2mp2ea000",
      "last_four" : "7857",
      "status" : "open"
  },
  ...
]
```

***

## Get Account

Retrieve a specific account by it's id.

```bash
curl https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000 \
  -u test_token_ky6igyqi3qxa4:
```

```json
{
    "enrollment_id" : "enr_oiin624rqaojse22oe000",
    "links" : {
      "balances" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/balances",
      "self" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000",
      "transactions" : "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions"
    },
    "institution" : {
      "name" : "Security Credit Union",
      "id" : "security_cu"
    },
    "type" : "credit",
    "name" : "Platinum Card",
    "subtype" : "credit_card",
    "currency" : "USD",
    "id" : "acc_oiin624kqjrg2mp2ea000",
    "last_four" : "7857",
    "status" : "open"
}
```

***

## Delete Account

This deletes your application's authorization to access the given account as addressed by its id. This does not delete the account itself.

Removing access will cancel billing for subscription billed products associated with the account, e.g. transactions.

```bash
curl -X DELETE https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000 \
  -u test_token_ky6igyqi3qxa4:
```

```json
// No response body, e.g. 204 No Content
```

***

## Delete Accounts

This deletes your application's authorization to access any account in the
enrollment, i.e. effectively deletes the enrollment. This does not delete
the accounts themselves.

Removing access will cancel billing for subscription billed products
associated with the enrollment, e.g. transactions.

```bash
curl -X DELETE https://api.teller.io/accounts \
  -u test_token_ky6igyqi3qxa4:
```

```json
// No response body, e.g. 204 No Content
```
