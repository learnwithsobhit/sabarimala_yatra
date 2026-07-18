# Android APK sideload (Aug 2026 delivery)

For the pilgrimage group (~70 phones), distribute a release APK — no Play Store required for Phase 1.

## Build

```bash
# From repo root — point API_BASE at your Railway (or other) HTTPS API
API_BASE=https://YOUR_RAILWAY_HOST scripts/build_apk.sh
```

Output: `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`

## Install on phones

1. Share the APK via WhatsApp / Drive / USB.
2. On Android: open the file → allow **Install unknown apps** for Files/Chrome.
3. Install → open **Swamy Sharanam** → login with roster phone + OTP.

## Notes

- Use **HTTPS** API in release builds (cleartext HTTP may be blocked on Android 9+).
- First open on Wi‑Fi: tap cloud download on Home to cache the trip pack.
- Signing: default Flutter debug/release keystore is fine for private sideload; use a real keystore before Play Store later.
- **Push notifications:** configure Firebase before the group APK — see [fcm-setup.md](fcm-setup.md).
