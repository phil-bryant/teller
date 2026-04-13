# Account Details (https://teller.io/docs/api/account/details)

The account details object contains the financial account's account number and routing information.

## Properties

-   `account_id` _(string)_ - The id of the account the account details belong to.

-   `account_number` _(string)_ - The account number.

-   `links` _(object)_ - An object containing links to related resources. A link indicates the enrollment supports that type of resource. Not every institution implements all of the capabilities that Teller supports. Your application should reflect on the contents of this object to determine what is supported by the financial institution.
    -   `self` _(string)_ - A self link to the account details.
    -   `account` _(string)_ - A link to the account that owns the details.

-   `routing_numbers` _(object)_ - An object containing the account details routing numbers.
    -   `ach` _(string (nullable))_ - The account's routing number for ACH transactions.
    -   `wire` _(string (nullable))_ - The account's wire routing number.
    -   `bacs` _(string (nullable))_ - The account's BACS sort code.

***

## Get Account Details

Returns the account's details.

```bash
curl https://api.teller.io/accounts/acc_oiin624iajrg2mp2ea000/details \
  -u test_token_ky6igyqi3qxa4:
```

```json
{
  "links" : {
      "account" : "https://api.teller.io/accounts/acc_oiin624iajrg2mp2ea000",
      "self" : "https://api.teller.io/accounts/acc_oiin624iajrg2mp2ea000/details"
  },
  "routing_numbers" : {
      "ach" : "066474405"
  },
  "account_id" : "acc_oiin624iajrg2mp2ea000",
  "account_number" : "142999287346"
}
```

***

## Account Details verification via Microdeposit

Account details are available instantly after an enrollment for the majority of
institutions supported by Teller. These institutions have the `verify.instant`
product in the response from the [Institutions API
endpoint](/docs/api/institutions). However, this is not possible for a number of
institutions (those that have `verify.microdeposit` products in the API response
from the [Institutions API endpoint](/docs/api/institutions)). To access
account details from these institutions, you can implement the 'Verify Account
Details via Microdeposit\` flow. Your customers will enter account and routing
numbers for the accounts that they would like to enroll in Teller Connect, and
Teller will send a microdeposit to the accounts to verify that they are
correct.

### Enabling / disabling the flow

To enable the flow, [initialize Teller
Connect](/docs/guides/connect#configuration-options) with `verify` specified among
the products using the `products` property. To disable the flow and only
enable institutions that provide account details instantly, specify
the `verify.instant` product instead.

If you don't need account details but would like to enroll users with the
institutions that require this flow to use other Teller products, don't
specify `verify` product when initializing Teller Connect. Your users won't be
prompted to enter account numbers when they enroll.

### Accessing Account Details

When using this flow, account details become available after a successful
verification: once we've confirmed that the microdeposit sent by us is present
among the account's transactions, we'll make the account details available via
the API. This usually happens within 3 business days. You can also subscribe to
an `account.number_verification.processed` [webhook](/docs/api/webhooks) to be
notified about completed verifications.

While the verification is pending, the `/accounts/:account_id/details` API
endpoint will return a `404 Not Found` error with the following body:

```json
{
  "error": {
    "code": "account_number_verification_pending",
    "message": "Account details are not yet available because the verification via microdeposit is pending"
  }
}
```

If we are not able to verify the details entered by the user within 7 calendar
days, the verification expires, and the `/accounts/:account_id/details` API
endpoint will start returning a `404 Not Found` error with the following body:

```json
{
  "error": {
    "code": "account_number_verification_expired",
    "message": "Account details are not available because the verification via microdeposit has expired"
  }
}
```

We'll also send a `account.number_verification.processed` webhook when the
verification expires.

### Testing the flow in Sandbox

To test this flow in [Sandbox](/docs/guides/sandbox), [initialize Teller
Connect](/docs/guides/connect#configuration-options) with `verify` product and use
`verify.microdeposit` as the username in Teller Connect. You'll get access to
two accounts called `Success` and `Failure`, and you'll be asked to enter the
account number and routing number for both. Enter any number that ends with the
account number suffix shown in Teller Connect and any valid routing number
(e.g. `110000000`).

After enrolling you can fetch account details to see what the response
looks like when the verification is pending. Verification is triggered by
fetching transactions: if you make an API call to fetch transactions for the
account called `Success`, a microdeposit transaction will be present in the
response and the account details verification will succeeed. You'll then be
able to fetch account details from the API.

If you make an API call to fetch transactions for the account called `Failure`,
there won't be a microdeposit transaciton present and the verification will
expire. If you make an API call to fetch account details, you'll get an error
saying that the verification has expired.

### Considerations

Consider using [`selectAccount` configuration
parameter](/docs/guides/connect#configuration-options) in Teller Connect to limit the
number of accounts your users enroll or let the user select which accounts they
want to enroll to avoid making users enter details for the accounts that you
don't need access to.

When a verification expires, the enrollment remains healthy and you might be
billed for it, so consider [disconnecting such
enrollments](/docs/api/accounts#delete-accounts) if you don't need access to the
enrollment.
