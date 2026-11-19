"""Customize Android scaffolding and configure deterministic TEST signing.

The bundled key is public and intentionally TEST ONLY. For app distribution,
provide a unique private keystore as GitHub Actions secrets (README_AR.md).
"""
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parent.parent
manifest = root / 'android/app/src/main/AndroidManifest.xml'
if not manifest.exists():
    raise SystemExit('Missing AndroidManifest.xml: run flutter create first')
text = manifest.read_text(encoding='utf-8')
text, count = re.subn(r'(<application\b[^>]*\bandroid:label=")[^"]*(")', r'\g<1>ممالك الحياة\2', text, count=1, flags=re.DOTALL)
# If the generated app has no label, insert a label on the application element.
if not count:
    text, count = re.subn(r'<application\b', '<application android:label="ممالك الحياة"', text, count=1)
    if not count:
        raise SystemExit('No Android <application> element found')
manifest.write_text(text, encoding='utf-8')

for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
    source = root / f'assets/android_icon/mipmap-{density}/ic_launcher.png'
    target = root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
    if not source.is_file():
        raise SystemExit(f'Missing launcher icon: {source}')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)

# A stable testing keystore solves different signatures on ephemeral CI runners.
# Do NOT use this test key for a published/store-distributed app.
kts = root / 'android/app/build.gradle.kts'
groovy = root / 'android/app/build.gradle'
if kts.is_file():
    build_file = kts
    data = kts.read_text(encoding='utf-8')
    anchor = '    buildTypes {'
    if data.count(anchor) != 1:
        raise SystemExit('Unsupported Android Gradle template: missing/duplicate buildTypes block')
    config = r"""    signingConfigs {
        create("mamlakatTest") {
            storeFile = file(System.getenv("KINGDOM_KEYSTORE_PATH") ?: "../../signing/dev_only_kingdom.jks")
            storePassword = System.getenv("KINGDOM_STORE_PASSWORD") ?: "mamlakat-install-test-2026"
            keyAlias = System.getenv("KINGDOM_KEY_ALIAS") ?: "mamlakat-dev"
            keyPassword = System.getenv("KINGDOM_KEY_PASSWORD") ?: "mamlakat-install-test-2026"
        }
    }
"""
    data = data.replace(anchor, config + anchor, 1)
    pattern = r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)'
    data, count = re.subn(pattern, 'signingConfig = signingConfigs.getByName("mamlakatTest")', data, count=1)
    if count != 1:
        raise SystemExit('Unsupported Android Gradle template: cannot locate release signingConfig')
    build_file.write_text(data, encoding='utf-8')
elif groovy.is_file():
    build_file = groovy
    data = groovy.read_text(encoding='utf-8')
    anchor = '    buildTypes {'
    if data.count(anchor) != 1:
        raise SystemExit('Unsupported Android Gradle template: missing/duplicate buildTypes block')
    config = r"""    signingConfigs {
        mamlakatTest {
            storeFile file(System.getenv('KINGDOM_KEYSTORE_PATH') ?: '../../signing/dev_only_kingdom.jks')
            storePassword System.getenv('KINGDOM_STORE_PASSWORD') ?: 'mamlakat-install-test-2026'
            keyAlias System.getenv('KINGDOM_KEY_ALIAS') ?: 'mamlakat-dev'
            keyPassword System.getenv('KINGDOM_KEY_PASSWORD') ?: 'mamlakat-install-test-2026'
        }
    }
"""
    data = data.replace(anchor, config + anchor, 1)
    data, count = re.subn(r'signingConfig\s+signingConfigs\.debug', 'signingConfig signingConfigs.mamlakatTest', data, count=1)
    if count != 1:
        raise SystemExit('Unsupported Android Gradle template: cannot locate release signingConfig')
    build_file.write_text(data, encoding='utf-8')
else:
    raise SystemExit('Missing Gradle build file: Android project creation failed')

print('Android label, launcher icon and release APK signing configured:', build_file)
