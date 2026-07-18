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

## Deploy (Railway)

See `apps/api/Dockerfile` and `infra/railway.toml`.

Production env (required):

| Var | Value |
| --- | --- |
| `DATABASE_URL` | Railway Postgres URL |
| `JWT_SECRET` | Long random string (≠ default) |
| `DEV_AUTH` | `0` (API refuses default JWT secret when this is off) |
| `SMS_WEBHOOK_URL` | HTTPS OTP delivery adapter; see [docs/otp-webhook.md](docs/otp-webhook.md) |
| `SMS_WEBHOOK_TOKEN` | Long random bearer token for the adapter |
| `UPLOAD_DIR` | `/data/uploads` (or volume path; used when `MEDIA_BACKEND=local`) |
| `MEDIA_BACKEND` | `s3` for prod media; needs `S3_BUCKET`, `AWS_*`, `MEDIA_PUBLIC_BASE_URL`/`S3_PUBLIC_URL` — see [docs/media-s3-setup.md](docs/media-s3-setup.md) |
| FCM vars | See [docs/fcm-setup.md](docs/fcm-setup.md) |

Release APK (HTTPS API only):

```bash
API_BASE=https://YOUR_RAILWAY_HOST ./scripts/build_apk.sh
```

Leader dry-run: install on 2–3 phones, Start count → Present → Stop, then Broadcasts + SOS.

## Licence

Private — for the yatra group.
