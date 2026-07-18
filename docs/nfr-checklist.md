# NFR checklist (Phase 1 gate)

Use before leader dry-run and APK distribution.

## Reliability / offline

- [ ] Home opens trip pack offline (itinerary, pass, broadcasts, lost tips, packing)
- [ ] Present tap works offline and syncs (banner shows pending count)
- [ ] Count export CSV available for paper backup

## Security / privacy

- [ ] `DEV_AUTH=0`, strong `JWT_SECRET`, `SMS_WEBHOOK_URL` set in prod
- [ ] Media files require signed URLs
- [ ] Tokens in secure storage (not plaintext prefs on device)
- [ ] No Aadhaar stored; medical notes not in RAG

## Push / chat

- [ ] Firebase configured (`isConfigured=true` + `google-services.json`)
- [ ] Count open push received on a test phone
- [ ] Chat refuses ungrounded answers; citations visible; ≥10 offline FAQ chips

## Accessibility

- [ ] TalkBack can activate **I am Present** on Home and Count
- [ ] System font scale 1.3× still usable on Home / Count
- [ ] Outdoor glare: primary buttons remain readable

## Compatibility

- **Min Android SDK:** API 26 (Android 8.0) — default Flutter `minSdk`; survey group phones before Aug 8
- APK ≤ ~50MB target; sideload guide in `docs/apk-sideload.md`

## Dry-run script (≤3 minutes)

1. Leader starts count “Assembly house”
2. 5 members mark Present (one offline then reconnect)
3. Leader reviews Not yet / Missing; marks one Present as helper
4. Export CSV / copy roster
5. Stop ready-to-march
6. Confirm broadcast + (if FCM live) notification
