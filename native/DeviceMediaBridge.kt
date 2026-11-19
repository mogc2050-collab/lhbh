package com.ibetoo.ibetoo_media

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.database.ContentObserver
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Android indexed media, artwork, duplicate checks and user-granted access. */
class DeviceMediaBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel=MethodChannel(messenger,"ibetoo.media/device")
    private val executor=Executors.newSingleThreadExecutor()
    private var pendingPermission: MethodChannel.Result?=null
    private val requestCode=7231
    private var changes:EventChannel.EventSink?=null
    private val observer=object:ContentObserver(Handler(Looper.getMainLooper())){
        override fun onChange(selfChange:Boolean) {
            changes?.success("changed")
        }
    }

    init{
        EventChannel(messenger,"ibetoo.media/changes").setStreamHandler(
            object:EventChannel.StreamHandler{
                override fun onListen(arguments:Any?, events:EventChannel.EventSink?){
                    changes=events
                }
                override fun onCancel(arguments:Any?){changes=null}
            })
        for(uri in listOf(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI)){
            activity.contentResolver.registerContentObserver(uri,true,observer)
        }
        channel.setMethodCallHandler { call,result ->
            when(call.method){
                "permissions" -> result.success(permissionState())
                "requestPermissions" -> requestPermissions(result)
                "scan","thumbnail","imagePreview","audioCache","duplicates" -> {
                    executor.execute {
                        try{
                            val value: Any = when(call.method){
                                "scan" -> scan(call.argument<String>("kind") ?: "audio")
                                "thumbnail" -> thumbnail(call.argument<String>("uri") ?: "")
                                "imagePreview" -> imagePreview(call.argument<String>("uri") ?: "")
                                "audioCache" -> cacheMedia(call.argument<String>("uri") ?: "")
                                else -> duplicates()
                            }
                            Handler(Looper.getMainLooper()).post{result.success(value)}
                        }catch(e:Exception){
                            Handler(Looper.getMainLooper()).post{
                                result.error("DEVICE_MEDIA",e.message,e.javaClass.simpleName)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun requiredPermissions():Array<String> {
        if(Build.VERSION.SDK_INT>=34)return arrayOf(
            Manifest.permission.READ_MEDIA_AUDIO,
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            Manifest.permission.POST_NOTIFICATIONS)
        if(Build.VERSION.SDK_INT>=33)return arrayOf(
            Manifest.permission.READ_MEDIA_AUDIO,
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.POST_NOTIFICATIONS)
        return arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }
    private fun granted(name:String)=activity.checkSelfPermission(name)==
        PackageManager.PERMISSION_GRANTED
    private fun permissionState():Map<String,Boolean>{
        if(Build.VERSION.SDK_INT>=33){
            val selected=Build.VERSION.SDK_INT>=34 &&
                granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
            return mapOf(
                "audio" to granted(Manifest.permission.READ_MEDIA_AUDIO),
                "video" to (granted(Manifest.permission.READ_MEDIA_VIDEO)||selected),
                "image" to (granted(Manifest.permission.READ_MEDIA_IMAGES)||selected),
                "notifications" to granted(Manifest.permission.POST_NOTIFICATIONS))
        }
        val media=granted(Manifest.permission.READ_EXTERNAL_STORAGE)
        return mapOf("audio" to media,"video" to media,"image" to media,
            "notifications" to true)
    }
    private fun requestPermissions(result:MethodChannel.Result){
        if(pendingPermission!=null){
            result.error("BUSY","Permission request already running",null);return
        }
        val pending=requiredPermissions().filter{!granted(it)}
        if(pending.isEmpty()){result.success(permissionState());return}
        pendingPermission=result
        activity.requestPermissions(pending.toTypedArray(),requestCode)
    }
    fun handlePermissionResult(code:Int):Boolean {
        if(code!=requestCode)return false
        pendingPermission?.success(permissionState())
        pendingPermission=null
        return true
    }

    private fun collection(kind:String):Uri=when(kind){
        "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        else -> throw IllegalArgumentException("Only indexed audio/video/images")
    }
    private fun scan(kind:String):List<Map<String,Any>>{
        if(permissionState()[kind]!=true)return emptyList()
        val coll=collection(kind)
        val cols=mutableListOf(
            MediaStore.MediaColumns._ID,MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.MIME_TYPE)
        if(Build.VERSION.SDK_INT>=29)cols.add(MediaStore.MediaColumns.RELATIVE_PATH)
        if(kind=="audio"){
            cols.add(MediaStore.Audio.Media.DURATION)
            cols.add(MediaStore.Audio.Media.ARTIST)
            cols.add(MediaStore.Audio.Media.ALBUM)
            cols.add(MediaStore.Audio.Media.ALBUM_ID)
        } else if(kind=="video"){
            cols.add(MediaStore.Video.Media.DURATION)
        }
        val records=ArrayList<Map<String,Any>>()
        val cur=activity.contentResolver.query(coll,cols.toTypedArray(),null,null,
            MediaStore.MediaColumns.DATE_ADDED+" DESC") ?: return records
        cur.use{c->
            fun text(name:String):String{
                val index=c.getColumnIndex(name)
                return if(index<0||c.isNull(index))"" else c.getString(index)?:""
            }
            fun number(name:String):Long{
                val index=c.getColumnIndex(name)
                return if(index<0||c.isNull(index))0L else c.getLong(index)
            }
            while(c.moveToNext()&&records.size<10000){
                val id=number(MediaStore.MediaColumns._ID)
                records.add(mapOf(
                    "id" to id,
                    "uri" to ContentUris.withAppendedId(coll,id).toString(),
                    "name" to text(MediaStore.MediaColumns.DISPLAY_NAME),
                    "kind" to kind,
                    "size" to number(MediaStore.MediaColumns.SIZE),
                    "date" to number(MediaStore.MediaColumns.DATE_ADDED),
                    "mime" to text(MediaStore.MediaColumns.MIME_TYPE),
                    "folder" to if(Build.VERSION.SDK_INT>=29)
                        text(MediaStore.MediaColumns.RELATIVE_PATH) else "",
                    "artist" to if(kind=="audio")text(MediaStore.Audio.Media.ARTIST) else "",
                    "album" to if(kind=="audio")text(MediaStore.Audio.Media.ALBUM) else "",
                    "albumId" to if(kind=="audio")number(MediaStore.Audio.Media.ALBUM_ID) else 0L,
                    "duration" to when(kind){
                        "audio" -> number(MediaStore.Audio.Media.DURATION)
                        "video" -> number(MediaStore.Video.Media.DURATION)
                        else -> 0L
                    }
                ))
            }
        }
        return records
    }

    private fun checkedUri(raw:String):Uri{
        val uri=Uri.parse(raw)
        if(uri.scheme!="content"||uri.authority!=MediaStore.AUTHORITY)
            throw IllegalArgumentException("Not an Android MediaStore URI")
        return uri
    }
    private fun thumbnail(raw:String):ByteArray {
        val uri=checkedUri(raw)
        var bitmap:Bitmap?=null
        if(Build.VERSION.SDK_INT>=29){
            try{bitmap=activity.contentResolver.loadThumbnail(
                uri,Size(192,192),null)}catch(_:Exception){}
        }
        if(bitmap==null){
            val retriever=MediaMetadataRetriever()
            try{
                retriever.setDataSource(activity,uri)
                val embedded=retriever.embeddedPicture
                bitmap=if(embedded!=null)BitmapFactory.decodeByteArray(
                    embedded,0,embedded.size) else retriever.frameAtTime
            }catch(_:Exception){}
            finally{retriever.release()}
        }
        val out=ByteArrayOutputStream()
        bitmap?.compress(Bitmap.CompressFormat.JPEG,78,out)
        return out.toByteArray()
    }
    private fun imagePreview(raw:String):ByteArray {
        val uri=checkedUri(raw)
        val bounds=BitmapFactory.Options()
        bounds.inJustDecodeBounds=true
        activity.contentResolver.openInputStream(uri)?.use{
            BitmapFactory.decodeStream(it,null,bounds)
        }
        var sample=1
        while(bounds.outWidth/sample>2048||bounds.outHeight/sample>2048){
            sample*=2
        }
        val opts=BitmapFactory.Options()
        opts.inSampleSize=sample
        val bitmap=activity.contentResolver.openInputStream(uri)?.use{
            BitmapFactory.decodeStream(it,null,opts)
        } ?: throw IllegalArgumentException("Cannot decode image")
        val bytes=ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG,90,bytes)
        bitmap.recycle()
        return bytes.toByteArray()
    }

    private fun cacheMedia(raw:String):String {
        val uri=checkedUri(raw)
        val mime=activity.contentResolver.getType(uri)?:""
        val ext=when{
            mime.contains("mpeg")->".mp3"
            mime.contains("mp4")->".m4a"
            mime.contains("ogg")->".ogg"
            mime.contains("flac")->".flac"
            mime.startsWith("video/")->".mp4"
            else->".m4a"
        }
        val id=uri.lastPathSegment?:"unknown"
        val target=File(activity.cacheDir,"ibetoo_current_"+id+ext)
        if(target.isFile&&target.length()>0)return target.absolutePath
        val limit=512L*1024*1024
        try{
            (activity.contentResolver.openInputStream(uri)
                ?:throw IllegalArgumentException("Media unavailable")).use{input->
                target.outputStream().use{output->
                    val bytes=ByteArray(65536)
                    var size=0L
                    while(true){
                        val count=input.read(bytes)
                        if(count<0)break
                        size+=count
                        if(size>limit)throw IllegalArgumentException("File exceeds cache limit")
                        output.write(bytes,0,count)
                    }
                }
            }
        }catch(e:Exception){target.delete();throw e}
        return target.absolutePath
    }

    /** First compare exact sizes, then stream SHA-256; never delete anything. */
    private fun duplicates():List<Map<String,Any>>{
        val candidates=mutableMapOf<Long,MutableList<String>>()
        for(kind in listOf("audio","video","image")){
            if(permissionState()[kind]!=true)continue
            for(row in scan(kind)){
                val size=row["size"] as Long
                if(size<=0L||size>512L*1024*1024)continue
                candidates.getOrPut(size){mutableListOf()}.add(row["uri"] as String)
            }
        }
        val results=mutableMapOf<String,MutableList<String>>()
        var inspected=0
        for(group in candidates.values.filter{it.size>1}){
            for(raw in group){
                if(inspected++>400)break
                try{
                    val digest=MessageDigest.getInstance("SHA-256")
                    activity.contentResolver.openInputStream(checkedUri(raw))?.use{input->
                        val buffer=ByteArray(65536)
                        while(true){
                            val n=input.read(buffer)
                            if(n<0)break
                            digest.update(buffer,0,n)
                        }
                        val hash=digest.digest().joinToString("") {
                            "%02x".format(it.toInt() and 0xff)
                        }
                        results.getOrPut(hash){mutableListOf()}.add(raw)
                    }
                }catch(_:Exception){}
            }
        }
        return results.values.filter{it.size>1}.map{
            mapOf("uris" to it)
        }
    }
    fun dispose(){
        activity.contentResolver.unregisterContentObserver(observer)
        changes=null
        executor.shutdown()
    }
}
