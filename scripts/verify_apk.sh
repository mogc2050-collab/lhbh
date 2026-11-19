#!/usr/bin/env bash
set -euo pipefail

APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
if [[ ! -s "$APK" ]]; then
  echo "ERROR: APK does not exist or is empty: $APK" >&2
  exit 2
fi

echo "== APK physical integrity =="
unzip -t "$APK" | tail -n 1

echo "== Look up Android SDK validation tools =="
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
if [[ ! -d "$SDK/build-tools" ]]; then
  echo "ERROR: Missing Android SDK build-tools at $SDK" >&2
  exit 2
fi
BUILD_TOOLS=$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)
TOOLS="$SDK/build-tools/$BUILD_TOOLS"
echo "Using $TOOLS"

"$TOOLS/apksigner" verify --verbose --print-certs "$APK"
"$TOOLS/zipalign" -c -v 4 "$APK" | tail -n 2
"$TOOLS/aapt" dump badging "$APK" | grep -E '^(package:|sdkVersion:|targetSdkVersion:|native-code:|application-label:|launchable-activity:)' || true

unzip -Z1 "$APK" > "${RUNNER_TEMP:-/tmp}/kingdom-apk-entries.txt"
if ! grep -qE '^lib/(arm64-v8a|armeabi-v7a)/libflutter.so$' "${RUNNER_TEMP:-/tmp}/kingdom-apk-entries.txt"; then
  echo 'ERROR: No ARM Flutter native runtime found in the universal APK' >&2
  exit 3
fi
if ! grep -q '^assets/flutter_assets/' "${RUNNER_TEMP:-/tmp}/kingdom-apk-entries.txt"; then
  echo 'ERROR: Flutter assets are missing' >&2
  exit 4
fi

echo "== SHA-256 of deliverable =="
sha256sum "$APK"
echo 'APK package, signatures, zip entries and Flutter runtime verified.'
