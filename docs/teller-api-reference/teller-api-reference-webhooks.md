# Webhooks (https://teller.io/docs/api/webhooks)

Learn how to register your application to receive and verify webhook notifications from Teller and be notified of events not represented in the Teller API itself

## When Webhooks Are Triggered

Teller sends webhook events when specific conditions or changes are detected in user enrollments or their financial data. Webhooks are triggered in response to these events, which represent meaningful state changes within the Teller system.

For example, the `transactions.processed` webhook is sent when Teller finds new transactions after polling a user’s connected financial institution. Teller performs these checks multiple times per day on a non-predictable schedule, but guarantees at least one polling attempt every 24 hours.

Another example is the `enrollment.disconnected` webhook, which is triggered when Teller determines that an enrollment’s connection to the institution is irrecoverably broken and cannot be automatically restored.

These events can interact. For instance, if Teller temporarily loses connectivity to an enrollment but hasn’t yet classified it as disconnected, it may not be able to access up-to-date account data. As a result, no `transactions.processed` events will be sent during that time. Webhooks resume once connectivity is restored or the enrollment is marked as disconnected.

## Registering Webhooks

To register a new webhook, you need to have a URL in your app that Teller can call. You can configure a new webhook from the Teller Dashboard under [Application Settings](https://teller.io/settings/application).

Now, whenever something of interest happens in your app, a webhook is fired off by Teller. In the next section, we'll look at how to consume webhooks.

## Consuming Webhooks

When your app receives a webhook request from Teller, check the `type` attribute to see what event caused it. The first part of the event type categorizes the payload type, e.g., `enrollment`, `transaction`, etc.

```json
{
  "id": "wh_oiffb5cocakqmksbkg000",
  "payload": {
    "enrollment_id": "enr_oiffb5cocakqmksbkg001",
    "reason": "disconnected.account_locked"
  },
  "timestamp": "2023-07-10T03:49:29Z",
  "type": "enrollment.disconnected"
}
```

In the example above, an enrollment has entered a disconnected state because the financial institution has completely locked the account. This may happen for legal reasons, because an account has been involved in fraud, or an attacker has repeatedly tried to login by guessing the end user's credentials.

## The Webhook Object

The webhook object has the following shape:

-   `id` _(string)_ - The id of the webhook event

-   `payload` _(object)_ - Event specific data or an empty object if `"type": "webhook.test"`

-   `timestamp` _(string)_ - The ISO 8601 timestamp of the event.

-   `type` _(string)_ - The type of the event, either:
    -   `enrollment.disconnected` — Sent when the enrollment disconnected
    -   `transactions.processed` — Sent when transactions are categorized by Teller's transaction enrichment
    -   `account.number_verification.processed` - Sent when account details verification via microdeposit has either suceeded or expired (see ['Verify Account Details via Microdeposit'](/docs/api/account/details#account-details-verification-via-microdeposit))
    -   `webhook.test` — A test event triggered from the [Application Settings](https://teller.io/settings/application) page. Use this to test your webhook implementation.

The shape of the `payload` depends on the event's `type`

## Payload shape

-   `enrollment_id` _(string)_ - The id of the affected enrollment

-   `reason` _(string)_ -

    > Available when `"type": "enrollment.disconnected"` only

    The reason the enrollment was disconnected. Possible values:

    -   `disconnected`
    -   `disconnected.account_locked`
    -   `disconnected.credentials_invalid`
    -   `disconnected.enrollment_inactive`
    -   `disconnected.user_action.captcha_required`
    -   `disconnected.user_action.contact_information_required`
    -   `disconnected.user_action.insufficient_permissions`
    -   `disconnected.user_action.mfa_required`
    -   `disconnected.user_action.web_login_required`

-   `transactions` _(array)_ -

    > Available when `"type": "transactions.processed"` only

    An array of categorized transactions. The shape of the transaction objects is described in the [Transactions](/docs/api/account/transactions) page

-   `account_id` _(string)_ -

    > Available when `"type": "account.number_verification.processed"` only

    The id of the account the details of which needed to be verified

-   `status` _(string)_ -

    > Available when `"type": "account.number_verification.processed"` only

    The status of the verification. Possible values:

    -   `completed`
    -   `expired`

## Verifying Messages

Teller signs every webhook event with all non-expired signing secrets, that only you and Teller know. You can get your signing secrets from the [Application Settings](https://teller.io/settings/application) page.

Teller sends a signature in the Teller-Signature HTTP header:

```
Teller-Signature: t=signature_timestamp,v1=signature_1,v1=signature_2,v1=...
```

Most of the time there will be only one non-expired signing secret, so the signature header will look like this:

```
Teller-Signature: t=signature_timestamp,v1=signature
```

To verify that the payload was created by Teller, you have to calculate the signature and it must be equal to the signature extracted from the signature header.

To calculate the signature:

-   Create `signed_message` by joining `signature_timestamp` and the request's JSON body with a . character
-   Compute HMAC with SHA-256 using the non-expired signing secret as the key and `signed_message` as the message

To prevent replay attacks you should reject we with a `signature_timestamp` (Unix time) older than 3 minutes.

## Expiring Secrets

When you have a policy to periodically roll secrets, Teller allows you to do it without a gap in signature verification.

To expire the current signing secret, go to the [Application Settings](https://teller.io/settings/application) page and select when the secret should expire, e.g. in 2 hours. When you press Save, Teller will create a new non-expired secret, and from that moment, Teller will sign all webhook events with both secrets until the old secret expires:

```
Teller-Signature: t=signature_timestamp,v1=signature_with_new_secret,v1=signature_with_old_secret
```

This gives you time to update your application with the new secret.
