"""Generate Android host for iBetoo Browser + Offline Media Library.
The Flutter Android project is recreated by CI, so this script is idempotent
and deliberately contains no DownloadManager permission or implementation.
"""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parent.parent
manifest=ROOT/"android/app/src/main/AndroidManifest.xml"
if not manifest.exists():
    raise SystemExit("Run flutter create --platforms android first.")
text=manifest.read_text("utf-8")
if "xmlns:tools=" not in text:
    text=text.replace("<manifest ",'<manifest xmlns:tools="http://schemas.android.com/tools" ',1)

permissions=[
    "android.permission.INTERNET",
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
    "android.permission.READ_MEDIA_AUDIO",
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.USE_BIOMETRIC",
]
added="\n".join(
    f'    <uses-permission android:name="{p}" />' for p in permissions)
added+='\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>'
text=text.replace("<application",added+"\n    <application",1)
text,n=re.subn(
    r'(<application\b[^>]*\bandroid:label=")[^"]*(")',
    r'\g<1>iBetoo Media\2',text,count=1,flags=re.DOTALL)
if n!=1:raise SystemExit("Application label missing")
text,n=re.subn(
    r'(<application\b[^>]*\bandroid:icon=")[^"]*(")',
    r'\g<1>@drawable/ibetoo_media_icon\2',text,count=1,flags=re.DOTALL)
if n!=1:raise SystemExit("Application icon missing")
text=re.sub(r'<application\b',
    '<application android:usesCleartextTraffic="false"',text,count=1)
text=re.sub(r'<activity\b',
    '<activity android:supportsPictureInPicture="true" android:resizeableActivity="true"',
    text,count=1)
extra="""
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
        <provider android:name="androidx.core.content.FileProvider"
            android:authorities="com.ibetoo.ibetoo_media.fileprovider"
            android:exported="false" android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/ibetoo_file_paths"/>
        </provider>
"""
text=text.replace("</application>",extra+"</application>",1)
manifest.write_text(text,"utf-8")

res=ROOT/"android/app/src/main/res"
drawable=res/"drawable"
drawable.mkdir(parents=True,exist_ok=True)
(drawable/"ibetoo_media_icon.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
  android:width="108dp" android:height="108dp"
  android:viewportWidth="108" android:viewportHeight="108">
  <path android:fillColor="#BA4164"
    android:pathData="M20,6 L88,6 Q102,6 102,20 L102,88 Q102,102 88,102 L20,102 Q6,102 6,88 L6,20 Q6,6 20,6 Z"/>
  <path android:fillColor="#FFFFFFFF"
    android:pathData="M35,27 L75,54 L35,81 Z"/>
</vector>
""","utf-8")
xml=res/"xml"
xml.mkdir(parents=True,exist_ok=True)
(xml/"ibetoo_file_paths.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
  <cache-path name="shared_media" path="."/>
</paths>
""","utf-8")

android_src=ROOT/"android/app/src/main/kotlin/com/ibetoo/ibetoo_media"
android_src.mkdir(parents=True,exist_ok=True)
for name in ("MainActivity.kt","DeviceMediaBridge.kt"):
    source=ROOT/"native"/name
    if not source.exists():raise SystemExit(f"Missing native/{name}")
    (android_src/name).write_text(source.read_text("utf-8"),"utf-8")

kts=ROOT/"android/app/build.gradle.kts"
groovy=ROOT/"android/app/build.gradle"
if kts.exists():
    gradle=kts.read_text("utf-8")
    anchor="    buildTypes {"
    if gradle.count(anchor)!=1:raise SystemExit("Gradle signing location not found")
    gradle=gradle.replace(anchor,'''    signingConfigs {
        create("ibetooDemo") {
            storeFile = file(System.getenv("MEDIA_KEYSTORE_PATH") ?: "../../signing/dev_only_ibetoo_media.jks")
            storePassword = System.getenv("MEDIA_STORE_PASSWORD") ?: "ibetoo-media-test-2026"
            keyAlias = System.getenv("MEDIA_KEY_ALIAS") ?: "ibetoo-media-dev"
            keyPassword = System.getenv("MEDIA_KEY_PASSWORD") ?: "ibetoo-media-test-2026"
        }
    }
'''+anchor,1)
    gradle,count=re.subn(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = signingConfigs.getByName("ibetooDemo")',gradle,count=1)
    if count!=1:raise SystemExit("Release signing assignment not found")
    kts.write_text(gradle,"utf-8")
elif groovy.exists():
    gradle=groovy.read_text("utf-8")
    anchor="    buildTypes {"
    gradle=gradle.replace(anchor,'''    signingConfigs {
        ibetooDemo {
            storeFile file(System.getenv('MEDIA_KEYSTORE_PATH') ?: '../../signing/dev_only_ibetoo_media.jks')
            storePassword System.getenv('MEDIA_STORE_PASSWORD') ?: 'ibetoo-media-test-2026'
            keyAlias System.getenv('MEDIA_KEY_ALIAS') ?: 'ibetoo-media-dev'
            keyPassword System.getenv('MEDIA_KEY_PASSWORD') ?: 'ibetoo-media-test-2026'
        }
    }
'''+anchor,1)
    gradle,count=re.subn(r'signingConfig\s+signingConfigs\.debug',
        'signingConfig signingConfigs.ibetooDemo',gradle,count=1)
    if count!=1:raise SystemExit("Release signing assignment not found")
    groovy.write_text(gradle,"utf-8")
else:raise SystemExit("Android Gradle app template unavailable")
print("iBetoo Media: offline library, media playback, permissions, biometric lock, browser. No downloader.")
