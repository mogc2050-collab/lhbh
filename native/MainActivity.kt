package com.ibetoo.ibetoo_media

import android.app.PictureInPictureParams
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Browser + offline library: there is deliberately NO DownloadManager here. */
class MainActivity: AudioServiceFragmentActivity() {
    private lateinit var deviceMedia:DeviceMediaBridge

    override fun configureFlutterEngine(flutterEngine:FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceMedia=DeviceMediaBridge(this,flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "ibetoo.media/platform").setMethodCallHandler{call,result->
            try {
                when(call.method){
                    "pip"->{
                        if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.O) {
                            result.success(enterPictureInPictureMode(
                                PictureInPictureParams.Builder().build()))
                        }else result.success(false)
                    }
                    "shareLocal"->{
                        val path=call.argument<String>("path") ?: ""
                        val name=call.argument<String>("name") ?: "file"
                        shareLocal(path,name)
                        result.success(null)
                    }
                    else->result.notImplemented()
                }
            }catch(e:Exception){
                result.error("IBETOO",e.message,e.javaClass.simpleName)
            }
        }
    }
    override fun onRequestPermissionsResult(
        requestCode:Int,permissions:Array<out String>,grantResults:IntArray
    ){
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if(::deviceMedia.isInitialized)deviceMedia.handlePermissionResult(requestCode)
    }
    private fun shareLocal(path:String,name:String){
        val source=File(path).canonicalFile
        val root=dataDir.canonicalFile
        if(!source.isFile||!source.path.startsWith(root.path+File.separator)){
            throw IllegalArgumentException("Sharing allowed only for app-owned files")
        }
        val clean=name.replace(Regex("[^a-zA-Z0-9._ ()\\u0600-\\u06FF]"),"_").take(120)
        val output=File(cacheDir,"share_"+System.currentTimeMillis()+"_"+clean)
        source.inputStream().use{src->
            output.outputStream().use{dest->src.copyTo(dest)}
        }
        val uri=FileProvider.getUriForFile(this,
            "com.ibetoo.ibetoo_media.fileprovider",output)
        val intent=Intent(Intent.ACTION_SEND)
            .setType(contentResolver.getType(uri) ?: "*/*")
            .putExtra(Intent.EXTRA_STREAM,uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(intent,"مشاركة"))
    }
}
