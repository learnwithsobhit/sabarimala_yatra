#!/usr/bin/env bash
# Build a release APK for sideload distribution (Phase 1 delivery channel).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${API_BASE:-https://YOUR_API_HOST}"

cd "$ROOT/apps/mobile"
flutter pub get
flutter build apk --release --dart-define=API_BASE="$API_BASE"

APK="$ROOT/apps/mobile/build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "APK ready:"
echo "  $APK"
echo ""
echo "Install on Android:"
echo "  1. Copy APK to phone (Drive / WhatsApp / USB)"
echo "  2. Allow Install unknown apps for the file manager"
echo "  3. Open the APK and install"
echo ""
echo "Rebuild with your live API, e.g.:"
echo "  API_BASE=https://api.example.com $0"
