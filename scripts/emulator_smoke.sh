#!/usr/bin/env bash
set -euo pipefail
APK="${1:-dist/iBetoo-Media.apk}"
PACKAGE='com.ibetoo.ibetoo_media'

echo '== Install signed APK on emulator =='
adb install -r "$APK"
echo '== Launch Arabic browser + library + downloads app =='
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 13

if ! adb shell pidof "$PACKAGE" >/dev/null; then
  echo 'ERROR: App failed to start, showing relevant Android errors:' >&2
  adb logcat -d -t 450 | grep -E -i 'Flutter|FATAL EXCEPTION|AndroidRuntime|ibetoo_media' | tail -100 || true
  exit 5
fi
echo 'PASS: New iBetoo Media APK installed and process started.'
