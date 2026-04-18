# Authentication (https://teller.io/docs/api/authentication)

Nearly all of the Teller API endpoints require authentication. In this guide we'll look at mTLS and HTTP Basic Auth, which are the different types of authentication used in the Teller API and when and why they are used.

## mTLS

In a normal TLS handshake the client uses the server's TLS certificate to authenticate its identity. Because the server is in possession of a certificate signed by a trusted certificate authority, the client is able to verify all of the handshake messages were sent by the server and there was no third-party eavesdropping on or worse, tampering with the channel. Sadly this allows the server to verify neither the identity of the client nor that an attacker isn't snooping or tampering with the channel. Unfortunately it's not uncommon to misconfigure TLS certificate validation, thereby invalidating all of the aforementioned guarantees. Given that the Teller API facilitates access to some of the most sensitive and private information possible, a scenario where Teller is not able to verify the integrity and confidentiality of the API is not something we can allow to happen.

**The Teller API uses mTLS to authenticate the API caller**. Teller issues client certificates that you use to connect to the Teller API. This allows both parties to mutually authenticate each other, and most importantly enables Teller to authenticate API clients even when API clients are not performing TLS verification correctly.

mTLS is **required** for all API requests that involve end-user data, i.e. all requests in `development` and `production`.

In the interests of getting up and running as quickly as possible client authentication is not required in the `sandbox` environment, because it does not involve real end-user data. If used, client certificates are validated in the `sandbox` environment. We recommend using client certificates as soon as possible in order to become familiarized with them.

```bash
curl --cert /path/to/cert.pem --key /path/to/key.pem https://api.teller.io
```

Always keep your private key safe and secret. You must never share or distribute your private key, e.g. embedding it in a mobile app. If you suspect your private key has been compromised, you must revoke the certificate in the Teller Dashboard and issue a new one.

## Access Token

Access tokens are created when an end-user successfully completes an enrollment using Teller Connect. An access token represents your authorization to access accounts at a given financial institution that the end-user has expressly given consent for. Access tokens are useless without a Teller client certificate, in fact they are useless without a client certificate belonging to the application the user consented giving access to. The Teller API will not even acknowledge an access token is correct without the correct certificate.

Access tokens are encoded using the HTTP Basic Auth scheme.

```bash
curl -u ACCESS_TOKEN: https://api.teller.io/accounts
```
