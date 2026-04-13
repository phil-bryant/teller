# Institutions (https://teller.io/docs/api/institutions)

> **Note**
>
> This is a beta API and as such the interface is subject to change

An Institution represents a Financial Institution that is supported by Teller.

## Properties

-   `id` _(string)_ - Teller id of the institution.

-   `name` _(string)_ - Name of the institution.

-   `products` _(array)_ - List of Teller's products supported for the institution.

***

## List Institutions

Returns a list of all institutions supported by Teller. There is no
pagination currently. Doesn't require authentication.

```bash
curl https://api.teller.io/institutions
```

```json
[
  {
    "name": "Chase",
    "id": "chase",
    "products": [
      "verify",
      "balance",
      "transactions",
      "identity"
    ]
  },
  ...
]
```
