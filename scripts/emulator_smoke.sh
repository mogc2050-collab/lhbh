#!/usr/bin/env bash
set -euo pipefail
APK="${1:-dist/Mamlakat-Al-Hayat.apk}"
PACKAGE='com.mamlakatlife.medieval_life'

echo '== Emulator information =='
adb shell getprop ro.build.version.release
adb shell getprop ro.product.cpu.abi

echo '== Test that Android itself can install the exact APK =='
adb install -r "$APK"

echo '== Launch the installed app =='
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 18

echo '== Ensure process is alive after startup =='
if ! adb shell pidof "$PACKAGE"; then
  echo 'ERROR: App process not found after launch. Relevant logcat below:' >&2
  adb logcat -d -t 300 | grep -E -i 'flutter|FATAL EXCEPTION|AndroidRuntime|mamlakat|medieval_life' | tail -100 || true
  exit 5
fi

echo 'PASS: APK installed, game launched, and process survived startup on an Android emulator.'
