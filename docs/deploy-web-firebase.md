# Web deploy (Firebase Hosting)

The Flutter app is deployed as a web build to Firebase Hosting.

- Firebase project: `swamy-sharanam`
- Live URL: https://swamy-sharanam.web.app
- Hosting config: [`apps/mobile/firebase.json`](../apps/mobile/firebase.json),
  project alias in [`apps/mobile/.firebaserc`](../apps/mobile/.firebaserc)

The API base URL is baked in at build time via `--dart-define=API_BASE`
(see [`apps/mobile/lib/core/api_client.dart`](../apps/mobile/lib/core/api_client.dart)),
so the site must be rebuilt whenever the API URL changes.

## Deploy

One command (build + deploy) — pass the deployed Railway API URL:

```bash
API_BASE=https://<your-api>.up.railway.app scripts/deploy_web.sh
```

Or manually:

```bash
cd apps/mobile
flutter build web --release --dart-define=API_BASE=https://<your-api>.up.railway.app
firebase deploy --only hosting --project swamy-sharanam
```

## Notes

- Push notifications (FCM) are disabled on web by design
  (see [`apps/mobile/lib/core/push_bootstrap.dart`](../apps/mobile/lib/core/push_bootstrap.dart)),
  so the web build has no device notifications; announcements/counts still work.
- The app serves media directly from the public S3 URLs, and uploads use
  presigned PUT. The S3 bucket CORS already allows `PUT`/`GET` from any origin;
  optionally tighten `AllowedOrigins` to `https://swamy-sharanam.web.app`.
- Since the web and API are both HTTPS and S3 is HTTPS, there is no mixed-content
  issue.
- First deploy of this repo was built against the local API for pipeline
  validation; re-run the deploy command above with the real `API_BASE` so login
  and data calls work.
