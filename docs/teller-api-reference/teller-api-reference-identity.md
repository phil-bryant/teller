# Identity (https://teller.io/docs/api/identity)

Identity provides you with all of the accounts the end-user granted your application access authorization along with beneficial owner identity information for each of them. Beneficial owner information is attached to each account as it's possible the end-user is not the beneficial owner, e.g. a corporate account, or there is more than one beneficial owner, e.g. a joint account the end-user shares with their partner.

## Properties

-   `type` _(string)_ - `person`, `organization` or `unknown`.

-   `names` _(array)_ - An array of `name` objects with the following shape: (can be an empty list)
    -   `type` _(string)_ - `name` or `alias`.
    -   `data` _(string)_ - Name of the person or organization.

-   `addresses` _(array)_ - An array of `address` objects. Can be an empty list.
    -   `primary` _(boolean)_ - Indicates if this is the owner's primary address (in case multiple addresses are provided).
    -   `data` _(object)_ -
        -   `street` _(string)_ - The street address.
        -   `city` _(string)_ - The name of the town or city.
        -   `region` _(string)_ - The state or region. For US addresses it's a 2-letter uppercase state code, e.g. "AL".
        -   `postal_code` _(string)_ - The zip or postal code. For US addresses it can be a 5-digit ZIP code or a ZIP+4 code: 5 and 4 digits separated with a hyphen.
        -   `country` _(string)_ - The ISO 3166-1 alpha-2 2-letter country codes, e.g. "US".

-   `phone_numbers` _(array)_ - An array of `phone_number` objects with the following shape: (can be an empty list)
    -   `type` _(string)_ - `mobile`, `home`, `work` or `unknown`.
    -   `data` _(string)_ - The phone number digits only or prefixed with a "+" if in an international (E.164) format.

-   `emails` _(array)_ - An array of `email` objects with the following shape: (can be an empty list)
    -   `data` _(string)_ - An email address.

***

## Get Identity

Returns an array of accounts with beneficial owner identity information attached. Each item in the list is an object of the following type:

### Properties

-   `account` _(object)_ - An `account` object. See the [documentation](/docs/api/accounts) for type information.

-   `owners` _(array)_ - An array of identity objects of the type defined [above](#properties).

```bash
curl https://api.teller.io/identity \
  -u test_token_ky6igyqi3qxa4:
```

```json
[
  {
      "account" : {
        "name" : "Essential Savings",
        "last_four" : "3528",
        "type" : "depository",
        "enrollment_id" : "enr_oiin624rqaojse22oe000",
        "id" : "acc_oiin624jqjrg2mp2ea000",
        "status" : "open",
        "links" : {
            "self" : "https://api.teller.io/accounts/acc_oiin624jqjrg2mp2ea000",
            "transactions" : "https://api.teller.io/accounts/acc_oiin624jqjrg2mp2ea000/transactions",
            "balances" : "https://api.teller.io/accounts/acc_oiin624jqjrg2mp2ea000/balances",
            "details" : "https://api.teller.io/accounts/acc_oiin624jqjrg2mp2ea000/details"
        },
        "institution" : {
            "id" : "security_cu",
            "name" : "Security Credit Union"
        },
        "subtype" : "savings",
        "currency" : "USD"
      },
      "owners" : [
        {
            "addresses" : [
              {
                  "primary" : true,
                  "data" : {
                    "postal_code" : "55305",
                    "street" : "4849 SYCAMORE FORK ROAD",
                    "region" : "MINNESOTA",
                    "country" : "US",
                    "city" : "HOPKINS"
                  }
              }
            ],
            "type" : "organization",
            "names" : [
              {
                  "data" : "URBAN GROCERIES INC",
                  "type" : "name"
              }
            ],
            "phone_numbers" : [
              {
                  "data" : "6667778888",
                  "type" : "mobile"
              }
            ],
            "emails" : [
              {
                  "data" : "urban_groceries_inc@example.com"
              }
            ]
        }
      ]
  },
...
]
```
