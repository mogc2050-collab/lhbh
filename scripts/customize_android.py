"""Generate Android host for iBetoo Media on GitHub Actions.
Pure Python stdlib, no Android Studio installation on the user's computer.
"""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
manifest = root / "android/app/src/main/AndroidManifest.xml"
if not manifest.exists():
    raise SystemExit("Run flutter create --platforms android before customize.")
text = manifest.read_text("utf-8")

# Android supports MediaSession/lock screen audio, native downloads and PiP.
if "xmlns:tools=" not in text:
    text = text.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

perms = [
 "android.permission.INTERNET",
 "android.permission.WAKE_LOCK",
 "android.permission.FOREGROUND_SERVICE",
 "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
 "android.permission.READ_MEDIA_AUDIO",
 "android.permission.READ_MEDIA_VIDEO",
 "android.permission.POST_NOTIFICATIONS",
]
inject = "\n".join(
 f'    <uses-permission android:name="{p}" />' for p in perms
)
if "<application" not in text:
    raise SystemExit("No Android application tag found.")
text = text.replace("<application", inject + '\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>\n    <application', 1)
text, count = re.subn(
    r'(<application\b[^>]*\bandroid:label=")[^"]*(")',
    r'\g<1>iBetoo Media\2', text, count=1, flags=re.DOTALL)
if not count:
    raise SystemExit("Manifest application label missing.")
text, count = re.subn(
    r'(<application\b[^>]*\bandroid:icon=")[^"]*(")',
    r'\g<1>@drawable/ibetoo_media_icon\2', text, count=1, flags=re.DOTALL)
if not count:
    raise SystemExit("Manifest application icon missing.")
text = re.sub(r'<application\b', '<application android:usesCleartextTraffic="false"',
              text, count=1)

# MainActivity is a subclass of AudioServiceActivity: mandatory for lock screen.
text = re.sub(r'<activity\b',
    '<activity android:supportsPictureInPicture="true" android:resizeableActivity="true"',
    text, count=1)

extra = r"""
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
        <provider android:name="androidx.core.content.FileProvider"
            android:authorities="com.ibetoo.ibetoo_media.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/ibetoo_file_paths" />
        </provider>
"""
text = text.replace("</application>", extra + "    </application>", 1)
manifest.write_text(text, "utf-8")

drawable = root / "android/app/src/main/res/drawable"
drawable.mkdir(parents=True, exist_ok=True)
(drawable / "ibetoo_media_icon.xml").write_text(r"""<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#FF6719"
        android:pathData="M16,5 L92,5 Q103,5 103,16 L103,92 Q103,103 92,103 L16,103 Q5,103 5,92 L5,16 Q5,5 16,5 Z"/>
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M39,25 L84,54 L39,83 Z"/>
    <path android:fillColor="#FFF3D5C2"
        android:pathData="M23,31 L30,31 L30,77 L23,77 Z"/>
</vector>
""", "utf-8")

resource = root / "android/app/src/main/res/xml"
resource.mkdir(parents=True, exist_ok=True)
(resource / "ibetoo_file_paths.xml").write_text(r"""<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="media_share" path="."/>
</paths>
""", "utf-8")

main = root / "android/app/src/main/kotlin/com/ibetoo/ibetoo_media/MainActivity.kt"
main.parent.mkdir(parents=True, exist_ok=True)
main.write_text(r'''package com.ibetoo.ibetoo_media

import android.app.DownloadManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URLConnection

class MainActivity: AudioServiceActivity() {
    private val channel = "ibetoo.media/downloads"
    private lateinit var deviceMedia: DeviceMediaBridge

    private val manager: DownloadManager
        get() = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceMedia = DeviceMediaBridge(this,flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                try {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    when(call.method) {
                        "enqueue" -> {
                            val url = args["url"] as? String ?: ""
                            val filename = args["filename"] as? String ?: "media-file"
                            val userAgent = args["userAgent"] as? String ?: ""
                            result.success(enqueue(url, filename, userAgent))
                        }
                        "query" -> {
                            val ids = args["ids"] as? List<*> ?: emptyList<Any>()
                            result.success(query(ids))
                        }
                        "copyToCache" -> {
                            val id = (args["id"] as Number).toLong()
                            result.success(copyToCache(id))
                        }
                        "open" -> {
                            showDownloaded((args["id"] as Number).toLong(), false)
                            result.success(null)
                        }
                        "share" -> {
                            showDownloaded((args["id"] as Number).toLong(), true)
                            result.success(null)
                        }
                        "shareLocal" -> {
                            shareLocal(args["path"] as String, args["name"] as String)
                            result.success(null)
                        }
                        "delete" -> {
                            manager.remove((args["id"] as Number).toLong())
                            result.success(null)
                        }
                        "showDownloads" -> {
                            startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
                            result.success(null)
                        }
                        "pip" -> {
                            if(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val ok=enterPictureInPictureMode(
                                    PictureInPictureParams.Builder().build())
                                result.success(ok)
                            }else result.success(false)
                        }
                        else -> result.notImplemented()
                    }
                }catch(e: Exception) {
                    result.error("MEDIA_NATIVE", e.message ?: e.javaClass.simpleName, null)
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if (::deviceMedia.isInitialized) deviceMedia.handlePermissionResult(requestCode)
    }

    private fun mime(filename: String): String {
        val extension = filename.substringAfterLast('.', "").lowercase()
        val mapped = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        return mapped ?: URLConnection.guessContentTypeFromName(filename)
            ?: "application/octet-stream"
    }

    private fun safeFilename(input: String): String {
        val filtered = input.filter { it.isLetterOrDigit() ||
            it in " ._-()" }.trim().trim('.').take(130)
        return if(filtered.isBlank()) "media-file" else filtered
    }

    private fun enqueue(url: String, filename: String, agent: String): Long {
        val uri = Uri.parse(url)
        if(uri.scheme != "https" || uri.host.isNullOrEmpty())
            throw IllegalArgumentException("Only HTTPS direct files are supported")
        val host = uri.host!!.lowercase()
        if(host == "youtube.com" || host.endsWith(".youtube.com") ||
            host == "youtu.be" || host.endsWith(".youtu.be")) {
            throw IllegalArgumentException("Use official YouTube playback/offline options")
        }
        val name = safeFilename(filename)
        val unique = System.currentTimeMillis().toString() + "_" + name
        val req = DownloadManager.Request(uri)
            .setTitle(name)
            .setDescription("iBetoo Media")
            .setMimeType(mime(name))
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(
                Environment.DIRECTORY_DOWNLOADS, "iBetooMedia/" + unique)
        if(agent.isNotBlank()) req.addRequestHeader("User-Agent", agent.take(300))
        val cookie = CookieManager.getInstance().getCookie(url)
        if(!cookie.isNullOrBlank()) req.addRequestHeader("Cookie", cookie)
        return manager.enqueue(req)
    }

    private fun query(ids: List<*>): List<Map<String,Any>> {
        val output = mutableListOf<Map<String,Any>>()
        for(value in ids){
            val id = (value as? Number)?.toLong() ?: continue
            val cursor = manager.query(DownloadManager.Query().setFilterById(id))
            cursor.use { c ->
                if(!c.moveToFirst()){
                    output.add(mapOf("id" to id, "status" to "missing",
                        "downloaded" to 0, "total" to -1))
                    return@use
                }
                val status = c.getInt(c.getColumnIndexOrThrow(
                    DownloadManager.COLUMN_STATUS))
                val loaded = c.getLong(c.getColumnIndexOrThrow(
                    DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = c.getLong(c.getColumnIndexOrThrow(
                    DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                val label = when(status){
                    DownloadManager.STATUS_PENDING -> "pending"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_SUCCESSFUL -> "success"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "unknown"
                }
                output.add(mapOf("id" to id, "status" to label,
                    "downloaded" to loaded, "total" to total))
            }
        }
        return output
    }

    private fun getUri(id: Long): Uri =
        manager.getUriForDownloadedFile(id)
            ?: throw IllegalArgumentException("Download is not ready")

    private fun copyToCache(id: Long): String {
        val uri = getUri(id)
        val name = manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            if(!cursor.moveToFirst())throw IllegalArgumentException("No download")
            cursor.getString(cursor.getColumnIndexOrThrow(
                DownloadManager.COLUMN_TITLE)) ?: "file.bin"
        }
        val file = File(cacheDir, "play_" + id.toString() + "_" + safeFilename(name))
        contentResolver.openInputStream(uri).use { input ->
            if(input==null)throw IllegalStateException("Cannot read downloaded file")
            file.outputStream().use { output -> input.copyTo(output) }
        }
        return file.absolutePath
    }

    private fun showDownloaded(id: Long, share: Boolean) {
        val uri = getUri(id)
        val type = manager.getMimeTypeForDownloadedFile(id) ?: "*/*"
        val intent = if(share)Intent(Intent.ACTION_SEND)
            .setType(type).putExtra(Intent.EXTRA_STREAM,uri)
        else Intent(Intent.ACTION_VIEW).setDataAndType(uri,type)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(intent,
            if(share)"مشاركة الملف" else "فتح الملف"))
    }

    private fun shareLocal(path: String, name: String) {
        val source=File(path).canonicalFile
        val root=dataDir.canonicalFile
        if(!source.path.startsWith(root.path+File.separator) ||
            !source.isFile) throw IllegalArgumentException("Invalid app-owned file")
        val copy=File(cacheDir, "share_" + System.currentTimeMillis() +
            "_" + safeFilename(name))
        source.inputStream().use { a ->
            copy.outputStream().use { b -> a.copyTo(b) }
        }
        val uri=FileProvider.getUriForFile(this,
            "com.ibetoo.ibetoo_media.fileprovider",copy)
        val intent=Intent(Intent.ACTION_SEND)
            .setType(mime(name))
            .putExtra(Intent.EXTRA_STREAM,uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(intent,"مشاركة الملف"))
    }
}
''', "utf-8")
native_bridge = root / "native/DeviceMediaBridge.kt"
if not native_bridge.is_file():
    raise SystemExit("Missing native/DeviceMediaBridge.kt")
(main.parent / "DeviceMediaBridge.kt").write_text(native_bridge.read_text("utf-8"), "utf-8")

kts = root / "android/app/build.gradle.kts"
groovy = root / "android/app/build.gradle"
if kts.is_file():
    data=kts.read_text("utf-8")
    anchor="    buildTypes {"
    if data.count(anchor) != 1:
        raise SystemExit("Unsupported Kotlin Android Gradle template")
    config=r'''    signingConfigs {
        create("ibetooDemo") {
            storeFile = file(System.getenv("MEDIA_KEYSTORE_PATH") ?: "../../signing/dev_only_ibetoo_media.jks")
            storePassword = System.getenv("MEDIA_STORE_PASSWORD") ?: "ibetoo-media-test-2026"
            keyAlias = System.getenv("MEDIA_KEY_ALIAS") ?: "ibetoo-media-dev"
            keyPassword = System.getenv("MEDIA_KEY_PASSWORD") ?: "ibetoo-media-test-2026"
        }
    }
'''
    data=data.replace(anchor,config+anchor,1)
    data,count=re.subn(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = signingConfigs.getByName("ibetooDemo")',data,count=1)
    if count!=1:raise SystemExit("Cannot find release signing config")
    kts.write_text(data,"utf-8")
elif groovy.is_file():
    data=groovy.read_text("utf-8")
    anchor="    buildTypes {"
    if data.count(anchor)!=1:raise SystemExit("Unknown Groovy Android template")
    config=r"""    signingConfigs {
        ibetooDemo {
            storeFile file(System.getenv('MEDIA_KEYSTORE_PATH') ?: '../../signing/dev_only_ibetoo_media.jks')
            storePassword System.getenv('MEDIA_STORE_PASSWORD') ?: 'ibetoo-media-test-2026'
            keyAlias System.getenv('MEDIA_KEY_ALIAS') ?: 'ibetoo-media-dev'
            keyPassword System.getenv('MEDIA_KEY_PASSWORD') ?: 'ibetoo-media-test-2026'
        }
    }
"""
    data=data.replace(anchor,config+anchor,1)
    data,count=re.subn(r'signingConfig\s+signingConfigs\.debug',
        'signingConfig signingConfigs.ibetooDemo',data,count=1)
    if count!=1:raise SystemExit("Cannot update Groovy signing")
    groovy.write_text(data,"utf-8")
else:
    raise SystemExit("Android Gradle app template not found")
print("iBetoo Media Android package, background service, downloads and PiP configured")
