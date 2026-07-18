# Swamy Sharanam

Greenfield Flutter + Rust companion for the Sabarimala group yatra (Aug 15–20, 2026).

**Product:** group ops (count sessions, assignments, broadcasts, expenses) + itinerary chatbot.  
**Stack:** `apps/api` (Rust / Axum / Postgres) · `apps/mobile` (Flutter) · `infra/docker-compose.yml`

Built from scratch — not forked from other projects.

## Quick start

### 1. Infrastructure

```bash
cd infra
docker compose up -d
```

Postgres: `localhost:5433` · Redis: `localhost:6380`

### 2. API

```bash
cp .env.example .env
cd apps/api
cargo run
```

Health: `GET http://127.0.0.1:8080/health`

On first boot the API seeds a demo trip and three rostered phones:

| Phone | Role | Dev OTP |
| --- | --- | --- |
| `9999000001` | leader | `123456` |
| `9999000002` | volunteer | `123456` |
| `9999000003` | swamy | `123456` |

### 3. Mobile

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE=http://127.0.0.1:8080
```

On a physical device, use your machine LAN IP for `API_BASE`.

## Count session (P0)

1. Leader/volunteer opens **Count** → **Start count**
2. Everyone taps **I am Present** (live board: Present / Not yet / Missing)
3. Leader taps **Stop count — ready to march** (warns if incomplete; `force` allowed)

## Leader tools (More tab)

- **Assignments** — Seed default Bus 1–3, hotels, train coaches (16315/16316); tap a member to assign
- **Broadcasts** — Send info/urgent messages to the group (FCM when configured)
- **Roster** — Member list + CSV import (leader)
- **Food distribution** — Start meal session; members tap Received; helpers tick pending (train/bus)
- **Packing checklist** — PDF packing items with personal progress
- **Memories** — Photo + video gallery; Swamy uploads need approval; leader/volunteer auto-approved. Uploads go direct to S3/CloudFront in prod (see [docs/media-s3-setup.md](docs/media-s3-setup.md))
- **Day notes / Mala / Feedback** — Phase 2 group notes, mala-removal reminders, lessons for next year
- **Roster → not traveling today** — excludes member from expected count headcount
- **If you are lost** — Rendezvous tips + SOS broadcast + call helpers (also on Home)
- Home cloud icon downloads an **offline trip pack** (itinerary + pass + announcements)
- **Count → I am Present** works offline (queues and syncs later)

## Chatbot

Uses trip knowledge chunks (+ PDF ingest via `cargo run --bin ingest_pdf`). Set `OPENAI_API_KEY` for embeddings + grounded LLM answers (`LLM_BACKEND=openai` or `qwen`); otherwise extractive fallback. Offline FAQ chips work without network.

## Auth

Roster OTP → short-lived **access JWT** (2h) + **refresh token** (30d, rotated). Production requires `SMS_WEBHOOK_URL` when `DEV_AUTH=0`.

## Push (FCM)

See [docs/fcm-setup.md](docs/fcm-setup.md). Without credentials the API still works; pushes are logged as skipped.

## APK sideload

See [docs/apk-sideload.md](docs/apk-sideload.md) and `scripts/build_apk.sh`.

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/auth/otp/request` | Roster-only |
| POST | `/auth/otp/verify` | JWT |
| GET | `/home/now` | Pass + broadcast + open count |
| GET | `/trips/:id/itinerary` | Day plan |
| POST/GET | `/count/sessions…` | Start / present / board / stop |
| GET/POST | `/announcements` | Broadcasts |
| GET/POST | `/roster` | List / CSV import (leader) |
| GET/POST | `/expenses` | Ledger + balances |
| POST | `/chat/ask` | Grounded FAQ over trip docs |
| GET | `/media`, `/media/mine`, `/media/pending` | Gallery / my uploads / moderation |
| POST | `/media/presign` → `/media/confirm` | Direct photo/video upload (S3 or local) |
| POST | `/auth/refresh` | Rotate access token |
| GET/POST | `/notes` | Day group notes |
| GET/POST | `/mala-reminders` | Mala removal reminders |
| GET/POST | `/feedback` | Post-trip lessons |
| POST | `/day-status` | Not traveling today |
| GET | `/trips` | Multi-year archive for member |
| POST | `/trips/:id/duplicate` | Clone itinerary for next season |
| POST | `/admin/knowledge/upload` | PDF/text knowledge CMS |
| POST | `/registration/interest` | Next-year registration interest |

## NFR / dry-run

See [docs/nfr-checklist.md](docs/nfr-checklist.md), [docs/fcm-setup.md](docs/fcm-setup.md), [docs/otp-webhook.md](docs/otp-webhook.md), [docs/pdf-ingestion.md](docs/pdf-ingestion.md).

**Min Android SDK:** API 26+.

## Deploy

Three moving parts, all currently live:

| Component | Platform | Where | Notes |
| --- | --- | --- | --- |
| API (Rust/Axum) | Railway | `https://api-production-f535.up.railway.app` | Docker build from `apps/api`, auto-runs migrations |
| Postgres (+pgvector) | Railway | private `postgres.railway.internal` | `CREATE EXTENSION vector` required |
| Web (Flutter web) | Firebase Hosting | https://swamy-sharanam.web.app | `API_BASE` baked in at build time |
| Native APK | sideload | — | `scripts/build_apk.sh` |

Detailed platform docs: [Railway (API + DB)](docs/deploy-railway.md) · [Firebase (web)](docs/deploy-web-firebase.md) · [S3 media](docs/media-s3-setup.md).

### Prerequisites

```bash
npm i -g firebase-tools            # web deploy
brew install railway               # or: npm i -g @railway/cli
railway login && firebase login    # interactive, one time
```

### A. Database — Railway Postgres (with pgvector)

The API runs `sqlx::migrate!` on every boot, so **you never run migrations by hand** — provisioning a database and deploying the API is enough. The one requirement is pgvector: migration `20260714000008_knowledge_embeddings.sql` executes `CREATE EXTENSION IF NOT EXISTS vector`, so the DB must support it (Railway's Postgres does — currently pgvector 0.8.5).

```bash
railway init --name swamy-sharanam     # create project (once)
railway add --database postgres        # provision Postgres
```

Verify pgvector (optional): connect to the DB's public URL and run `CREATE EXTENSION IF NOT EXISTS vector;`.

### B. API — Railway

Deployed from the `apps/api` directory so the Docker build context matches the Dockerfile's `COPY` paths. Build config lives in [`apps/api/railway.json`](apps/api/railway.json) (Dockerfile builder + `/health` healthcheck).

```bash
cd apps/api
railway add --service api                       # create the API service (once)
railway variables --service api --skip-deploys \
  --set 'DATABASE_URL=${{Postgres.DATABASE_URL}}' \
  --set 'PORT=8080' \
  --set 'DEV_AUTH=1' --set 'DEV_OTP_CODE=123456' \
  --set 'JWT_SECRET=<long-random-string>' \
  --set 'MEDIA_BACKEND=s3' \
  --set 'S3_BUCKET=sabarimala-yatra-media' \
  --set 'AWS_REGION=ap-south-1' \
  --set 'S3_PUBLIC_URL=https://sabarimala-yatra-media.s3.ap-south-1.amazonaws.com' \
  --set 'AWS_ACCESS_KEY_ID=<key>' --set 'AWS_SECRET_ACCESS_KEY=<secret>' \
  --set 'OPENAI_API_KEY=<key>'                  # chatbot embeddings + grounded answers
railway up --service api --ci                   # build + deploy (streams logs)
railway domain --service api --port 8080        # generate public HTTPS domain
```

Wait for `/health` to return `{"status":"ok","database":"up"}`. On first boot the API seeds the demo trip, three rostered phones, itinerary, packing checklist, and starter knowledge chunks.

**Port:** the app binds `0.0.0.0:$PORT` when `PORT` is set (Railway provides it; we pin `PORT=8080`), falling back to `BIND_ADDR`, then `0.0.0.0:8080`.

#### Railway env vars

Pilot (fixed OTP — any rostered phone logs in with `DEV_OTP_CODE`):

| Var | Value |
| --- | --- |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (private networking reference) |
| `PORT` | `8080` |
| `DEV_AUTH` | `1` |
| `DEV_OTP_CODE` | `123456` (choose your own) |
| `JWT_SECRET` | Long random string, ≥24 chars |
| `MEDIA_BACKEND` + `S3_*` / `AWS_*` | S3 media — see [docs/media-s3-setup.md](docs/media-s3-setup.md) |
| `OPENAI_API_KEY` | Chatbot embeddings + LLM answers (optional; extractive fallback without it) |

Production (real OTP) — replace the pilot auth block:

| Var | Value |
| --- | --- |
| `DEV_AUTH` | `0` (API refuses the default JWT secret when off) |
| `SMS_WEBHOOK_URL` | HTTPS OTP delivery adapter — see [docs/otp-webhook.md](docs/otp-webhook.md) |
| `SMS_WEBHOOK_TOKEN` | Long random bearer token |
| FCM vars | See [docs/fcm-setup.md](docs/fcm-setup.md) |

### C. Chatbot knowledge base (RAG)

`ingest_pdf` is **not** in the deployed image — run it locally against the Railway DB to embed the trip document. It force-loads the repo `.env` (which points at local Postgres), so run it with the compiled binary from a neutral directory, or temporarily point `DATABASE_URL` at Railway:

```bash
cd apps/api
DATABASE_URL='<railway-postgres-public-url>' OPENAI_API_KEY='<key>' \
  cargo run --bin ingest_pdf -- ../../Shabarimala2026_Aug15-20.pdf <trip_uuid>
```

Re-run after uploading a new/updated trip PDF so embeddings stay in sync.

### D. Web — Firebase Hosting

`API_BASE` is compiled in, so **rebuild whenever the API URL changes**. One command builds + deploys:

```bash
API_BASE=https://api-production-f535.up.railway.app scripts/deploy_web.sh
```

Cache headers in [`apps/mobile/firebase.json`](apps/mobile/firebase.json) mark entry files (`main.dart.js`, `flutter_bootstrap.js`, service worker) `no-cache` so returning users don't get stuck on a stale bundle. FCM push is disabled on web by design.

### E. Native APK

```bash
API_BASE=https://api-production-f535.up.railway.app ./scripts/build_apk.sh
```

### Redeploying after changes

- **API code:** `cd apps/api && railway up --service api --ci`
- **Env var:** `railway variables --service api --set 'KEY=VALUE'` (auto-restarts)
- **Web:** re-run `scripts/deploy_web.sh` with the current `API_BASE`

Leader dry-run: install on 2–3 phones, Start count → Present → Stop, then Broadcasts + SOS.

## Licence

Private — for the yatra group.
