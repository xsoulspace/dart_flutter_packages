# xsoulspace_inference_xai

Last Answer's public Grok client. xAI registers this app. The package
does not embed the Grok CLI client id, send CLI identity headers, or
read another app's auth file.

Sign-in throws `client_not_registered` before any network call until a
client id is compiled in:

```text
--dart-define=LAST_ANSWER_GROK_CLIENT_ID=...
--dart-define=LAST_ANSWER_GROK_API_BASE=...   # optional, default https://api.x.ai/v1
```

## Registration packet

| Fact | Value |
| --- | --- |
| App | Last Answer |
| Referrer | `last-answer` |
| Redirect | `http://127.0.0.1:56123/callback` |
| Client | Public, PKCE S256, no secret |
| Grants | authorization code + PKCE, refresh token, RFC 8628 device code |
| Issuer | `https://auth.x.ai` |
| Scopes | `openid profile email offline_access api:access` |
| Inference | `POST {apiBase}/responses`, `GET {apiBase}/models` |

Plan access is the `api:access` scope. The account key is the OIDC
`subject`. A busy redirect port is refused. It is not replaced.

ID-token signatures are not verified against issuer JWKS yet. Tool
parameter schemas are open objects. Streaming emits one delta after the
full response. None of that is a live plan receipt.
