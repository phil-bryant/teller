# Errors (https://teller.io/docs/api/errors)

Learn how error conditions are expressed in the Teller API

Teller uses standard HTTP response status codes to indicate the success or failure of a request. Status codes in the 2xx range denote a successful request. Status codes in the 4xx range denote a client error, e.g. not using a client certificate to make the request, a problem with the user access token, etc. Status codes in the 5xx range denote a problem on our end, e.g. a bank is unavailable and it's not possible or otherwise doesn't make sense to gracefully handle the exception.

> **Note**
>
> Failed requests do not generate billing events

## Status Codes

Here is a list of status codes currently in use by the Teller API

-   `200 OK` _()_ - A successful request.

-   `400 Bad Request` _()_ - The request was unacceptable. Used when a request that requires a client certificate is made without one.

-   `401 Unauthorized` _()_ - A request was made without an access token where one was required.

-   `403 Forbidden` _()_ - A request was made with an invalid or revoked access token.

-   `404 Not Found` _()_ - The requested resource was not found.

-   `410 Gone` _()_ - Indicates that the resource requested is no longer available and that condition is permanent, e.g. because a financial account was closed.

-   `422 Unprocessable Entity` _()_ - A request was made with an invalid request body.

-   `429 Too Many Requests` _()_ - Indicates that the application has exceeded its rate limit by sending too many requests in a given time period and that this request was denied.

-   `502 Bad Gateway` _()_ - The financial institution is unavailable, or a 500 level response was received when making a request to the financial institution, and a graceful fallback is not possible, e.g. a payment instruction.

## The Error Object

Detailed information about the error condition is returned in the response body as a JSON object.

```json
{
  "error": {
      "code": "bad_request",
      "message": "Missing certificate: Retry request using your Teller client certificate."
  }
}
```

-   `error` _(object)_ - An object describing the error condition.
    -   `code` _(string)_ - The error condition.
    -   `message` _(string)_ - A human readable string describing the error and how to resolve it.

## Enrollment Errors

From time to time enrollments can enter an unhealthy state, meaning Teller is unable to use it until the end-user takes the required action. When your application makes a request involving a disconnected enrollment Teller returns a 404 status code with an error code beginning with `enrollment.disconnected`.

> **Note**
>
> To restore an unhealthy enrollment initialize Teller Connect in update mode and direct the user to reconnect.

When an enrollment enters a disconnected state, Teller can send a [webhook event](/docs/api/webhooks) of type `enrollment.disconnected`.

```json
{
  "error": {
    "code": "enrollment.disconnected.user_action.mfa_required",
    "message": "User MFA is required."
  }
}
```

## Enrollment Error Codes

-   `enrollment.disconnected` _()_ - A generic error used for when no more information is available.

-   `enrollment.disconnected.account_locked` _()_ - Access to the account has been restricted by the financial institution.

-   `enrollment.disconnected.credentials_invalid` _()_ - The end-user changed their authentication credentials to access the financial institution.

-   `enrollment.disconnected.enrollment_inactive` _()_ - The enrollment has become disconnected due to inactivity.

-   `enrollment.disconnected.user_action.captcha_required` _()_ - The end-user is required to solve a CAPTCHA.

-   `enrollment.disconnected.user_action.contact_information_required` _()_ - The end-user is required to update their contact information.

-   `enrollment.disconnected.user_action.insufficient_permissions` _()_ - The end-user does not have the required permissions to perform the requested operation.

-   `enrollment.disconnected.user_action.mfa_required` _()_ - The end-user is required to complete a MFA challenge.

-   `enrollment.disconnected.user_action.web_login_required` _()_ - The end-user is required to login to the financial institution's web online-banking, e.g. to accept FI terms and conditions.
