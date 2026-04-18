# Introduction (https://teller.io/docs/api)

Welcome to the Teller API Reference

The Teller API is organized around REST. Resources have predictable, self-describing URLs and contain links to related resources. Our API accepts form-encoded requests and returns JSON encoded responses. It uses standard HTTP status codes, authentication, and methods in their usual ways.

You can use the Teller API in sandbox mode, which is free, does not call out to any real banks, and does not affect your live data. The access token you use determines whether your request is handled in the live or sandbox environments.

Access tokens for the live environment are obtained using Teller Connect when a user successfully connects a bank account to your Teller application.

> **Note**
>
> Learn how to integrate Teller Connect into your application with the [Teller Connect integration guide](/docs/guides/connect)

## Rate Limits

Teller enforces rate limits to maintain system stability and protect the integrity of connections with financial institutions. These limits help ensure that excessive traffic does not trigger hostile or defensive measures from banks, which could impact connectivity for all customers.

Free-tier accounts are subject to rate limits. The exact thresholds are not publicly documented and cannot be adjusted. If you’re on the free plan, design your integration to be efficient and resilient under these constraints.

Production plans benefit from significantly higher rate limits. In practice, it’s rare for production applications to hit these ceilings under normal usage. The limits are designed to balance performance with reliability—preventing overload scenarios that could degrade service quality for other customers.

Rate limiting is not just about controlling traffic. It is part of being a responsible participant in the broader financial ecosystem. By moderating the volume of requests sent to institutions, we help maintain long-term access, reduce the risk of disruption, and demonstrate respect for the operational boundaries of ths we connect to. It reflects our commitment to being a good steward of shared infrastructure—for your users, for other developers, and for the institutions themselves.

If your application triggers rate limits, Teller will respond with an HTTP 429 status code. Your system should back off and retry after an appropriate delay.

## API Entrypoint

```bash
https://api.teller.io/
```

## Versioning

Teller uses dated versions with the latest one being 2020-10-12. By default all API requests will use the version specified in the [Teller Dashboard](https://teller.io/settings/application).

In order to test a new version, you can request it using the Teller-Version HTTP header. Once you are ready to upgrade to a new version permanently, you can do so from the dashboard. You will have 72 hours to rollback to the version you were previously using.

```bash
curl https://api.teller.io/accounts -H "Teller-Version: 2019-07-01"
```
