package com.ibetoo.ibetoo_media

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Android's indexed music/video library, not a fake imported-files list.
 * No MANAGE_EXTERNAL_STORAGE permission and no access to private app files.
 * Media queries are executed off the Android UI thread.
 */
class DeviceMediaBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ibetoo.media/device")
    private val executor = Executors.newSingleThreadExecutor()
    private var permissionReply: MethodChannel.Result? = null
    private val permissionCode = 7231

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "permissions" -> result.success(permissionState())
                "requestPermissions" -> requestPermissions(result)
                "scan" -> {
                    val kind = call.argument<String>("kind") ?: "audio"
                    if (kind != "audio" && kind != "video") {
                        result.error("BAD_KIND","Only audio/video media are supported",null)
                    } else {
                        executor.execute {
                            try {
                                val rows = scan(kind)
                                Handler(Looper.getMainLooper()).post { result.success(rows) }
                            } catch (e: Exception) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("SCAN_FAILED",e.message,null)
                                }
                            }
                        }
                    }
                }
                "audioCache" -> {
                    val raw = call.argument<String>("uri") ?: ""
                    executor.execute {
                        try {
                            val path = cacheMedia(raw)
                            Handler(Looper.getMainLooper()).post { result.success(path) }
                        } catch(e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("COPY_FAILED",e.message,null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.READ_MEDIA_AUDIO,Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.POST_NOTIFICATIONS)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun permissionState(): Map<String,Boolean> {
        fun granted(name: String): Boolean =
            activity.checkSelfPermission(name)==PackageManager.PERMISSION_GRANTED
        return if (Build.VERSION.SDK_INT >= 33) {
            mapOf("audio" to granted(Manifest.permission.READ_MEDIA_AUDIO),
                "video" to granted(Manifest.permission.READ_MEDIA_VIDEO),
                "notifications" to granted(Manifest.permission.POST_NOTIFICATIONS))
        } else {
            val media = granted(Manifest.permission.READ_EXTERNAL_STORAGE)
            mapOf("audio" to media,"video" to media,"notifications" to true)
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (permissionReply != null) {
            result.error("BUSY","Another permission request is in progress",null)
            return
        }
        val missing = requiredPermissions().filter {
            activity.checkSelfPermission(it)!=PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(permissionState())
            return
        }
        permissionReply = result
        activity.requestPermissions(missing.toTypedArray(),permissionCode)
    }

    fun handlePermissionResult(requestCode: Int): Boolean {
        if (requestCode != permissionCode) return false
        permissionReply?.success(permissionState())
        permissionReply=null
        return true
    }

    private fun scan(kind: String): List<Map<String, Any>> {
        val permission = permissionState()[kind] ?: false
        if (!permission) return emptyList()
        val audio = kind=="audio"
        val collection = if (audio) MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val idColumn = MediaStore.MediaColumns._ID
        val titleColumn = MediaStore.MediaColumns.DISPLAY_NAME
        val projection = arrayOf(
            idColumn,titleColumn,MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_ADDED,MediaStore.MediaColumns.MIME_TYPE,
            if (audio) MediaStore.Audio.Media.DURATION else MediaStore.Video.Media.DURATION
        )
        val order = MediaStore.MediaColumns.DATE_ADDED + " DESC"
        val results = ArrayList<Map<String, Any>>()
        val cursor = activity.contentResolver.query(
            collection,projection,null,null,order) ?: return results
        cursor.use { c ->
            val idPos=c.getColumnIndexOrThrow(idColumn)
            val titlePos=c.getColumnIndexOrThrow(titleColumn)
            val sizePos=c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val datePos=c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
            val mimePos=c.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val durationPos=c.getColumnIndexOrThrow(
                if (audio) MediaStore.Audio.Media.DURATION else MediaStore.Video.Media.DURATION)
            while (c.moveToNext() && results.size<5000) {
                val id=c.getLong(idPos)
                val name=c.getString(titlePos) ?: "media"
                val uri=ContentUris.withAppendedId(collection,id)
                results.add(mapOf(
                    "id" to id,
                    "uri" to uri.toString(),
                    "name" to name,
                    "kind" to kind,
                    "size" to c.getLong(sizePos),
                    "date" to c.getLong(datePos),
                    "duration" to c.getLong(durationPos),
                    "mime" to (c.getString(mimePos) ?: "")
                ))
            }
        }
        return results
    }

    /**
     * For just_audio implementations which don't accept SAF content:// URIs,
     * copy only the current track into the app-owned cache. Never preload
     * the entire music library. Limit the copy size to avoid filling storage.
     */
    private fun cacheMedia(raw: String): String {
        val uri=Uri.parse(raw)
        if (uri.scheme!="content" ||
            uri.authority != MediaStore.AUTHORITY) {
            throw IllegalArgumentException("Only indexed MediaStore URIs allowed")
        }
        val id=uri.lastPathSegment ?: throw IllegalArgumentException("Missing media ID")
        val mime=activity.contentResolver.getType(uri) ?: ""
        val ext=when {
            mime.contains("mpeg") -> ".mp3"
            mime.contains("mp4") -> ".m4a"
            mime.contains("aac") -> ".aac"
            mime.contains("ogg") -> ".ogg"
            mime.contains("flac") -> ".flac"
            mime.contains("wav") -> ".wav"
            mime.startsWith("video/") -> ".mp4"
            else -> ".mp3"
        }
        val target=File(activity.cacheDir,"ibetoo_track_" + id + ext)
        if(target.isFile && target.length()>0) return target.absolutePath
        val maxBytes=180L*1024*1024
        val source=activity.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("File no longer accessible")
        source.use { input ->
            target.outputStream().use { out ->
                val buffer=ByteArray(65536)
                var bytes=0L
                while(true) {
                    val n=input.read(buffer)
                    if(n<0)break
                    bytes+=n
                    if(bytes>maxBytes) {
                        target.delete()
                        throw IllegalArgumentException("Media exceeds the 180 MB audio-cache limit")
                    }
                    out.write(buffer,0,n)
                }
            }
        }
        return target.absolutePath
    }

    fun dispose() { executor.shutdown() }
}
