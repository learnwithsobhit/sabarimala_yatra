# Railway deploy (API)

1. Create a Railway project with **Postgres** (and optional Redis).
2. Deploy from `apps/api` using [`apps/api/Dockerfile`](../apps/api/Dockerfile) / [`infra/railway.toml`](../infra/railway.toml).
3. Set variables:

```bash
DATABASE_URL=<railway-postgres-url>
JWT_SECRET=<long-random-string>
DEV_AUTH=0
SMS_WEBHOOK_URL=https://your-sms-adapter.example.com/send-otp
SMS_WEBHOOK_TOKEN=<long-random-token>
BIND_ADDR=0.0.0.0:$PORT
UPLOAD_DIR=/data/uploads
# optional
OPENAI_API_KEY=
FCM_SERVICE_ACCOUNT_PATH=...   # or FCM_PROJECT_ID / FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY
```

See [Production OTP webhook](otp-webhook.md) for its request contract.

4. Attach a volume for `UPLOAD_DIR` if you want memories to persist.
5. Health check: `GET https://YOUR_HOST/health`
6. Build the group APK:

```bash
API_BASE=https://YOUR_HOST ./scripts/build_apk.sh
```

7. Leader dry-run on 2–3 phones before Aug 8 distribution (see README).
