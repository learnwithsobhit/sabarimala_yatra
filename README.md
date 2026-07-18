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
- **Memories** — Photo gallery; Swamy uploads need approval; leader/volunteer auto-approved
- **If you are lost** — Rendezvous tips + SOS broadcast + call helpers (also on Home)
- Home cloud icon downloads an **offline trip pack** (itinerary + pass + announcements)
- **Count → I am Present** works offline (queues and syncs later)

## Chatbot

Uses trip knowledge chunks. Set `OPENAI_API_KEY` for GPT-4o-mini grounded answers; otherwise extractive fallback.

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

## Deploy (Railway)

See `apps/api/Dockerfile` and `infra/railway.toml`.

Production env (required):

| Var | Value |
| --- | --- |
| `DATABASE_URL` | Railway Postgres URL |
| `JWT_SECRET` | Long random string (≠ default) |
| `DEV_AUTH` | `0` (API refuses default JWT secret when this is off) |
| `UPLOAD_DIR` | `/data/uploads` (or volume path) |
| FCM vars | See [docs/fcm-setup.md](docs/fcm-setup.md) |

Release APK (HTTPS API only):

```bash
API_BASE=https://YOUR_RAILWAY_HOST ./scripts/build_apk.sh
```

Leader dry-run: install on 2–3 phones, Start count → Present → Stop, then Broadcasts + SOS.

## Licence

Private — for the yatra group.
