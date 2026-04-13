# Payments (https://teller.io/docs/api/account/payments)

> **Note**
>
> This is a beta API and as such the interface is subject to change

The payments resource allows you to send payments to yourself or a 3rd party on behalf of the end-user from their account. Currently the only supported payment scheme is Zelle, but others will be added in the future.

## Zelle

Zelle payments can be initiated from checking accounts. The funds are debited immediately from the payer account and are usually received by the beneficiary instantly. In cases where the receiving financial institution is not a member of the Zelle network, the funds will settle via ACH with the beneficiary receiving the funds around 3 days after.

***

## Create a Payee

Creates a beneficiary for sending payments from the given account.

The financial institution may require the account owner to perform MFA when creating a payee. If MFA is required the response body from Teller will contain the property `connect_token`. The token is then used to initialize Teller Connect (see `connectToken` in the [Teller Connect Guide](/docs/guides/connect)), which will prompt the user with the steps required to save the payee. Your implementation must handle this case.

### Request Properties

-   `scheme` _(string)_ - `zelle` for Zelle payments.

-   `address` _(string)_ - The email address or cellphone number of the payment beneficiary.

-   `name` _(string)_ - The payment beneficiary's name.

-   `type` _(string)_ - Whether the payment beneficiary is a `person` or `business`.

```bash
curl -X POST https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payees \
  -u test_token_ky6igyqi3qxa4: \
  -H 'Content-Type: application/json' \
  -d '{
    "scheme": "zelle",
    "address": "jackson.lewis@teller.io",
    "name": "Jackson Lewis",
    "type": "person"
  }'
```

```json
// The financial institution requires the end-user
// to perform MFA to complete the payment
{
  "connect_token": "xxxxxxxxxxxxxx"
}
```

```json
{
  "scheme": "zelle",
  "address": "jackson.lewis@teller.io",
  "name": "Jackson Lewis",
  "type": "person",
  "account_id": "acc_oiin624kqjrg2mp2ea000",
  "links": {
    "account": "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000"
  }
}
```

***

## Discover Supported Payment Schemes

First, check the links collection in the [account entity](/docs/api/account/details#get-account-details). If the `payments` element is not present, the account does not support payment origination. If the `payments` element is present, send an `OPTIONS` request to the payments resource to see which payment schemes are supported.

Currently, only Zelle is supported. Additional payment schemes will be added in the future.

```bash
curl -X OPTIONS https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payments
  -u test_token_ky6igyqi3qxa4:
```

```json
{
  "schemes": [
    {
      "name": "zelle",
    }
  ]
}
```

***

## Initiate a Payment

Initiates a payment to the beneficiary from the given account.

The financial institution may require the account owner to perform MFA before executing the payment request. If MFA is required the response body from Teller will contain the property `connect_token`. The token is then used to initialize Teller Connect (see `connectToken` in the [Teller Connect Guide](/docs/guides/connect)), which will prompt the user with the steps required to execute the payment. Your implementation must handle this case.

This endpoint supports idempotent requests. Use the `Idempotency-Key` request header with a unique value per payment request. We store the key and keep the behavior associated to it for 72 hours.

### Request Properties

-   `amount` _(string)_ - The payment amount in dollars and cents (optional) as a string, e.g. "13.37", "10.00", "5".

-   `memo` _(string)_ - A short description of the nature of the payment.

-   `payee` _(object)_ - An object with the attributes of the payee. To make a payment to an existing payee, it's sufficient to specify the payee's `scheme` and `address` only. To make a payment to a new payee, specify all payee's attributes.

```bash
curl -X POST https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payments \
  -u test_token_ky6igyqi3qxa4: \
  -H 'Content-Type: application/json' \
  -d '{
    "amount": "10.48",
    "memo": "Drinks",
    "payee": {
      "scheme": "zelle",
      "address": "jackson.lewis@teller.io"
    }
  }'
```

```bash
curl -X POST https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payments \
  -u test_token_ky6igyqi3qxa4: \
  -H 'Content-Type: application/json' \
  -d '{
    "amount": "10.48",
    "memo": "Drinks",
    "payee": {
      "scheme": "zelle",
      "address": "jackson.lewis@teller.io",
      "name": "Jackson Lewis",
      "type": "person"
    }
  }'
```

```json
// The financial institution requires the end-user
// to perform MFA to complete the payment
{
  "connect_token": "xxxxxxxxxxxxxx"
}
```

```json
{
  "id": "zpay_o2iauakr4qme4v7uku000",
  "amount": "10.48",
  "memo": "Drinks",
  "reference": "GQ3C2MRQGIZC2MBXFUZDMLJVHEZDILKENFXG4ZLS",
  "date": "2023-09-04",
  "payee": {
    "scheme": "zelle",
    "type": "person",
    "name": "Jackson Lewis",
    "address": "jackson.lewis@teller.io",
  },
  "links": {
    "self": "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payments/zpay_o2iauakr4qme4v7uku000",
    "account": "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000"
  }
}
```

***

## List Payments

Returns a list of all payments that have been initiated via Teller API.

```bash
curl https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payments \
  -u test_token_ky6igyqi3qxa4:
```

```json
[
  {
    "id": "zpay_o2iauakr4qme4v7uku000",
    "amount": "10.48",
    "memo": "Drinks",
    "reference": "GQ3C2MRQGIZC2MBXFUZDMLJVHEZDILKENFXG4ZLS",
    "date": "2023-09-04",
    "payee": {
      "scheme": "zelle",
      "type": "person",
      "name": "Jackson Lewis",
      "address": "jackson.lewis@teller.io",
    },
    "links": {
      "self": "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payments/zpay_o2iauakr4qme4v7uku000",
      "account": "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000"
    }
  }
,
  ...
]
```

***

## Get Payment

Retrieve a specific payment by its id.

```bash
curl https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payments/zpay_o2iauakr4qme4v7uku000 \
  -u test_token_ky6igyqi3qxa4:
```

```json
{
  "id": "zpay_o2iauakr4qme4v7uku000",
  "amount": "10.48",
  "memo": "Drinks",
  "reference": "GQ3C2MRQGIZC2MBXFUZDMLJVHEZDILKENFXG4ZLS",
  "date": "2023-09-04",
  "payee": {
    "scheme": "zelle",
    "type": "person",
    "name": "Jackson Lewis",
    "address": "jackson.lewis@teller.io",
  },
  "links": {
    "self": "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/payments/zpay_o2iauakr4qme4v7uku000",
    "account": "https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000"
  }
}
```
