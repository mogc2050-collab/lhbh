"""Generate Android host for iBetoo Browser + Offline Media Library.
The Flutter Android project is recreated by CI, so this script is idempotent
and supports system-managed HTTPS file downloads.
"""
from pathlib import Path
import os
import re
import shutil
import time
import urllib.error
import urllib.request

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
  <path android:fillColor="#3478F6"
    android:pathData="M22,6 L86,6 Q102,6 102,22 L102,86 Q102,102 86,102 L22,102 Q6,102 6,86 L6,22 Q6,6 22,6 Z"/>
  <path android:fillColor="#FFFFFFFF"
    android:pathData="M50,44 L61,44 L61,79 L50,79 Z"/>
  <path android:fillColor="#FFFFFFFF"
    android:pathData="M55.5,26 m-7,0 a7,7 0,1 0,14 0 a7,7 0,1 0,-14 0"/>
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
for name in ("MainActivity.kt","DeviceMediaBridge.kt","GeckoEngine.kt","GeckoBridge.kt","GeckoPrompts.kt"):
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

# ---- GeckoView engine (Firefox engine, not Android WebView) ----
ext_src=ROOT/"native"/"web_extensions"
ext_dst=ROOT/"android/app/src/main/assets/web_extensions"
if not (ext_src/"aflaak-core"/"manifest.json").exists():
    raise SystemExit("Missing native/web_extensions/aflaak-core")
shutil.copytree(ext_src,ext_dst,dirs_exist_ok=True)

def _http(url,method="GET",timeout=60):
    last=None
    for i in range(3):
        try:
            req=urllib.request.Request(url,method=method,
                headers={"User-Agent":"ibetoo-media-ci"})
            with urllib.request.urlopen(req,timeout=timeout) as r:
                return r.status,(r.read() if method=="GET" else b"")
        except urllib.error.HTTPError as e:
            if e.code in (404,403,410):return e.code,b""
            last=e
        except Exception as e:
            last=e
        time.sleep(3*(i+1))
    raise last

def gecko_version():
    """Newest stable GeckoView whose AAR is really published (not just listed)."""
    forced=os.environ.get("GECKOVIEW_VERSION","").strip()
    if forced:return forced
    base="https://maven.mozilla.org/maven2/org/mozilla/geckoview/geckoview/"
    _,raw=_http(base+"maven-metadata.xml")
    xml=raw.decode("utf-8")
    versions=re.findall(r"<version>([^<]+)</version>",xml)
    stable=[v.strip() for v in versions if re.fullmatch(r"\d+\.\d+\.\d{8,}",v.strip())]
    stable.sort(key=lambda v:tuple(int(x) for x in v.split(".")),reverse=True)
    rel=re.search(r"<release>([^<]+)</release>",xml) or re.search(r"<latest>([^<]+)</latest>",xml)
    fallback=rel.group(1).strip() if rel else (stable[0] if stable else "")
    for v in stable[:8]:
        for ext in ("aar","pom"):
            try:
                code,_=_http(f"{base}{v}/geckoview-{v}.{ext}","HEAD",30)
            except Exception:
                code=0
            if code==200:
                print(f"GeckoView {v}: {ext} is published")
                return v
        print(f"GeckoView {v}: artifact not published yet, trying older release")
    if not fallback:raise SystemExit("Cannot resolve a GeckoView release")
    return fallback

GECKO=gecko_version()
print("GeckoView version:",GECKO)
app_gradle=kts if kts.exists() else groovy
g=app_gradle.read_text("utf-8")
g=re.sub(r"JavaVersion\.VERSION_(?:1[01]|8)","JavaVersion.VERSION_17",g)
g=re.sub(r'jvmTarget\s*=\s*"(?:1[01]|8)"','jvmTarget = "17"',g)
g=re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion",
         "minSdk = 26" if kts.exists() else "minSdkVersion 26",g,count=1)
if kts.exists():
    g+=f'''

repositories {{
    maven {{ url = uri("https://maven.mozilla.org/maven2/") }}
}}

dependencies {{
    implementation("org.mozilla.geckoview:geckoview:{GECKO}")
}}
'''
else:
    g+=f'''

repositories {{
    maven {{ url "https://maven.mozilla.org/maven2/" }}
}}

dependencies {{
    implementation "org.mozilla.geckoview:geckoview:{GECKO}"
}}
'''
app_gradle.write_text(g,"utf-8")


# ---- Build hardening: R8/JNI keep rules, lint, packaging, Gradle memory ----
proguard=ROOT/"android/app/proguard-ibetoo.pro"
proguard.write_text("""# GeckoView calls Java through JNI: renaming/removing these breaks the engine.
-keep class org.mozilla.geckoview.** { *; }
-keep class org.mozilla.gecko.** { *; }
-keep class org.mozilla.thirdparty.** { *; }
-keep class org.mozilla.javascript.** { *; }
-dontwarn org.mozilla.**
-dontwarn com.google.android.play.core.**
-dontwarn javax.annotation.**
-dontwarn org.jetbrains.annotations.**
-dontwarn org.checkerframework.**
-dontwarn com.google.errorprone.annotations.**
-keep class com.ibetoo.ibetoo_media.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
""","utf-8")

g=app_gradle.read_text("utf-8")
if kts.exists():
    g+='''

android {
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
    packaging {
        resources {
            pickFirsts += setOf("META-INF/versions/9/OSGI-INF/MANIFEST.MF")
            excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*", "META-INF/NOTICE*", "META-INF/INDEX.LIST")
        }
        jniLibs {
            pickFirsts += setOf("**/libc++_shared.so")
        }
    }
    buildTypes {
        getByName("release") {
            proguardFiles("proguard-ibetoo.pro")
        }
    }
}

// GeckoView 160+ declares a minCompileSdk (37.2) newer than the SDK Flutter uses.
// It is only AAR metadata: the engine is precompiled, so skip that check.
tasks.configureEach {
    if (name.contains("AarMetadata", ignoreCase = true)) {
        enabled = false
    }
}
'''
else:
    g+='''

android {
    lint {
        checkReleaseBuilds false
        abortOnError false
    }
    packaging {
        resources {
            pickFirsts += ['META-INF/versions/9/OSGI-INF/MANIFEST.MF']
            excludes += ['/META-INF/{AL2.0,LGPL2.1}', 'META-INF/DEPENDENCIES',
                'META-INF/LICENSE*', 'META-INF/NOTICE*', 'META-INF/INDEX.LIST']
        }
        jniLibs {
            pickFirsts += ['**/libc++_shared.so']
        }
    }
    buildTypes {
        release {
            proguardFiles 'proguard-ibetoo.pro'
        }
    }
}

// GeckoView 160+ declares a minCompileSdk (37.2) newer than the SDK Flutter uses.
// It is only AAR metadata: the engine is precompiled, so skip that check.
tasks.configureEach { t ->
    if (t.name.toLowerCase().contains('aarmetadata')) {
        t.enabled = false
    }
}
'''
app_gradle.write_text(g,"utf-8")

# GeckoView + R8 + dexing is heavy; a daemon killed for lack of RAM prints no
# "error:" line at all, so cap heap sizes to fit a 7 GB runner.
props=ROOT/"android/gradle.properties"
lines=props.read_text("utf-8").splitlines() if props.exists() else []
keep=("org.gradle.jvmargs","kotlin.daemon.jvmargs","org.gradle.workers.max",
      "org.gradle.parallel")
lines=[l for l in lines if not l.split("=",1)[0].strip() in keep]
lines+=[
    "org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -XX:+HeapDumpOnOutOfMemoryError",
    "kotlin.daemon.jvmargs=-Xmx2g",
    "org.gradle.workers.max=2",
    "org.gradle.parallel=false",
]
props.write_text("\n".join(lines)+"\n","utf-8")

print("iBetoo Media: GeckoView browser, offline library, playback, biometric lock, and Android downloads.")
