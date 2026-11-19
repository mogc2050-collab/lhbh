#!/usr/bin/env bash
set -euo pipefail
APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
if [[ ! -s "$APK" ]]; then echo "APK missing" >&2; exit 2; fi
unzip -t "$APK" | tail -1
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
TOOLS="$SDK/build-tools/$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)"
"$TOOLS/apksigner" verify --verbose --print-certs "$APK"
"$TOOLS/zipalign" -c -v 4 "$APK" | tail -2
"$TOOLS/aapt" dump badging "$APK" | grep -E '^(package:|application-label:|launchable-activity:)'
"$TOOLS/aapt" dump badging "$APK" | grep -q "com.ibetoo.ibetoo_media" || { echo 'Wrong app package!'; exit 3; }
unzip -Z1 "$APK" | grep -qE 'lib/(arm64-v8a|armeabi-v7a)/libflutter.so' || { echo 'Flutter ARM runtime missing'; exit 4; }
sha256sum "$APK"
echo 'Signed media app verified.'
