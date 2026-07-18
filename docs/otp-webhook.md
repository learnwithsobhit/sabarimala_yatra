# Production OTP webhook

When `DEV_AUTH=0`, the API requires `SMS_WEBHOOK_URL`. It sends:

```json
{
  "phone_e164": "+919999000001",
  "code": "123456",
  "message": "Your Swamy Sharanam login code is 123456. It expires in 10 minutes.",
  "expires_in_seconds": 600
}
```

If `SMS_WEBHOOK_TOKEN` is set, the request includes
`Authorization: Bearer <token>`. The adapter must return a `2xx` response only
after the SMS provider accepts the message. Any other response makes the OTP
request fail and removes the unusable challenge.

The adapter can connect to MSG91, Twilio Verify, AWS SNS, or another approved
provider without coupling provider credentials to this API.

Production controls:

- OTP requests are limited to one per minute and five per 15 minutes per phone.
- A challenge expires after 10 minutes and locks after five incorrect attempts.
- Keep the webhook on HTTPS and use a long random bearer token.
- Configure Indian DLT registration and an approved OTP template when required.
