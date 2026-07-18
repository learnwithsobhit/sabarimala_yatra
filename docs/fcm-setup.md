# Firebase Cloud Messaging setup (Aug 2026)

Push is optional for local web/dev. For the sideload APK, configure Firebase once so **count open/close**, **broadcasts**, and **SOS** reach phones.

**Status:** Client bootstrap + server FCM HTTP v1 are implemented. Live push requires your Firebase project credentials (cannot be committed). Follow this checklist, then test on two physical devices.

## Checklist

- [ ] Firebase project created
- [ ] Android app registered (`org.swamysharnam.swamy_sharanam`)
- [ ] `google-services.json` at `apps/mobile/android/app/google-services.json`
- [ ] `flutterfire configure` → `lib/firebase_options.dart` with `isConfigured = true`
- [ ] API has `FCM_SERVICE_ACCOUNT_PATH` or `FCM_*` env vars
- [ ] API log shows `FCM push enabled (HTTP v1)`
- [ ] Two devices: count open → both receive high-priority notification

## 1. Firebase project

1. Create a project at [Firebase Console](https://console.firebase.google.com/).
2. Add an **Android** app with package `org.swamysharnam.swamy_sharanam`.
3. Download `google-services.json` → place at  
   `apps/mobile/android/app/google-services.json`  
   (Gradle applies the Google Services plugin only when this file exists.)

## 2. Flutter options

From `apps/mobile`:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

That overwrites `lib/firebase_options.dart`. Then set:

```dart
static const bool isConfigured = true;
```

at the top of `DefaultFirebaseOptions` (if FlutterFire does not add that flag, keep the flag and set it to `true` after paste).

## 3. API service account (Railway / local)

1. Firebase Console → Project settings → **Service accounts** → Generate new private key.
2. On the API host, either:

```bash
# Preferred
FCM_SERVICE_ACCOUNT_PATH=/secret/firebase-sa.json
```

or discrete env vars:

```bash
FCM_PROJECT_ID=your-project-id
FCM_CLIENT_EMAIL=firebase-adminsdk-...@....iam.gserviceaccount.com
FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

Restart the API. Logs should show `FCM push enabled (HTTP v1)`.

## 4. Verify on devices

1. Install APK built with Firebase options + `google-services.json`:
   ```bash
   ./scripts/build_apk.sh
   ```
2. Login on two phones → allow notifications.
3. Leader starts a **count** or sends a broadcast → phones should receive a high-priority notification.
4. API log: `FCM fan-out complete ok=…`.

Without credentials, the API still stores announcements and logs how many tokens *would* have been notified. Client skips FCM when `isConfigured == false` (safe for Chrome/web).
