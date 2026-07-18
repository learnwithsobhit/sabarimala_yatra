# Railway deploy (API)

The API ships as a Docker image ([`apps/api/Dockerfile`](../apps/api/Dockerfile)) and
runs migrations automatically at startup (`sqlx::migrate!`). Health check: `GET /health`.

## 1. Postgres (must have pgvector)

Add a Postgres database to the project. Migration
[`20260714000008_knowledge_embeddings.sql`](../apps/api/migrations/20260714000008_knowledge_embeddings.sql)
runs `CREATE EXTENSION IF NOT EXISTS vector`, so the database **must support
pgvector** or the API fails on first boot. Use Railway's pgvector-capable
Postgres (verify `CREATE EXTENSION vector;` succeeds in the DB's Query tab).

## 2. API service build settings

The Dockerfile copies `Cargo.toml`, `src`, `migrations` with paths relative to
`apps/api`, so the Docker build context must be that folder:

- **Root Directory** = `apps/api`  (important — otherwise the build can't find `Cargo.toml`)
- **Builder** = Dockerfile, **Dockerfile Path** = `Dockerfile`
- **Healthcheck Path** = `/health`

These are captured in [`apps/api/railway.json`](../apps/api/railway.json), so deploying
from `apps/api` (via `railway up` or a service whose Root Directory is `apps/api`)
applies them automatically. The CLI flow:

```bash
cd apps/api
railway add --service api        # once
railway up --service api --ci    # build + deploy
```

## 3. Variables

Pilot (fixed dev OTP — any rostered phone logs in with `DEV_OTP_CODE`):

```bash
PORT=8080                        # app binds 0.0.0.0:$PORT (falls back to BIND_ADDR, then :8080)
DATABASE_URL=${{Postgres.DATABASE_URL}}
DEV_AUTH=1
DEV_OTP_CODE=123456              # choose your own
JWT_SECRET=<long-random-string, >=24 chars>

# Media -> AWS S3 (bucket already provisioned in ap-south-1)
MEDIA_BACKEND=s3
S3_BUCKET=sabarimala-yatra-media
AWS_REGION=ap-south-1
S3_PUBLIC_URL=https://sabarimala-yatra-media.s3.ap-south-1.amazonaws.com
AWS_ACCESS_KEY_ID=<key>
AWS_SECRET_ACCESS_KEY=<secret>

# optional
OPENAI_API_KEY=                  # chatbot embeddings / grounded answers
```

Production (real OTP delivery) instead of the pilot block above:

```bash
DEV_AUTH=0
SMS_WEBHOOK_URL=https://your-sms-adapter.example.com/send-otp
SMS_WEBHOOK_TOKEN=<long-random-token>
```

See [Production OTP webhook](otp-webhook.md) for the request contract. FCM push
vars (`FCM_SERVICE_ACCOUNT_PATH` or `FCM_PROJECT_ID`/`FCM_CLIENT_EMAIL`/`FCM_PRIVATE_KEY`)
are optional and only needed for native push.

## 4. Deploy + domain

1. Deploy the service and wait for `/health` to report `{"database":"up"}`.
2. Generate a public domain — `railway domain --service api --port 8080`
   (or Settings -> Networking -> Generate Domain, target port `8080`).
3. Note the HTTPS URL, e.g. `https://<svc>.up.railway.app` — this is the
   `API_BASE` for the web app / APK.

## 5. Optional: seed the chatbot knowledge base

`ingest_pdf` is not in the image; run it locally against the Railway DB:

```bash
cd apps/api
DATABASE_URL=<railway-postgres-url> OPENAI_API_KEY=<key> \
  cargo run --bin ingest_pdf -- ../../Shabarimala2026_Aug15-20.pdf
```

## 6. Point the frontend at the API

- Web (Firebase Hosting): see [deploy-web-firebase.md](deploy-web-firebase.md).
- Native APK: `API_BASE=https://YOUR_HOST ./scripts/build_apk.sh`
