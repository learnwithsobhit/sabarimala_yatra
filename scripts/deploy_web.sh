#!/usr/bin/env bash
# Build the Flutter web app and deploy it to Firebase Hosting.
#
# The API base URL is baked in at build time, so pass the deployed Railway URL:
#   API_BASE=https://your-api.up.railway.app scripts/deploy_web.sh
#
# Defaults to the local API for a quick smoke test if API_BASE is unset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${API_BASE:-http://127.0.0.1:8080}"
FIREBASE_PROJECT="${FIREBASE_PROJECT:-swamy-sharanam}"

echo "Building Flutter web with API_BASE=$API_BASE"
cd "$ROOT/apps/mobile"
flutter pub get
flutter build web --release --dart-define=API_BASE="$API_BASE"

echo "Deploying to Firebase Hosting (project: $FIREBASE_PROJECT)"
firebase deploy --only hosting --project "$FIREBASE_PROJECT"

echo ""
echo "Deployed. Live at: https://$FIREBASE_PROJECT.web.app"
echo "If the API base changes, re-run with API_BASE=<url> $0"
