package com.ibetoo.ibetoo_media

import android.app.Activity
import android.content.Context
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.mozilla.geckoview.GeckoView

/** Connects Flutter to GeckoEngine: method channel, event channel, platform view. */
class GeckoBridge(private val activity: Activity, engine: FlutterEngine) {
    private val prompts = GeckoPrompts { activity }

    init {
        val messenger = engine.dartExecutor.binaryMessenger
        EventChannel(messenger, "aflaak/gecko/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    GeckoEngine.sink = if (events == null) null else TabEventSink { events.success(it) }
                }
                override fun onCancel(arguments: Any?) { GeckoEngine.sink = null }
            },
        )
        MethodChannel(messenger, "aflaak/gecko").setMethodCallHandler { call, result ->
            try {
                val id = call.argument<String>("tabId")
                val tab = id?.let { GeckoEngine.tabs[it] }
                when (call.method) {
                    "create" -> {
                        GeckoEngine.create(
                            activity, id!!, call.argument<Boolean>("private") == true,
                            call.argument<String>("containerId"), prompts,
                        )
                        result.success(null)
                    }
                    "load" -> { tab?.load(call.argument<String>("url") ?: "about:blank"); result.success(null) }
                    "back" -> { tab?.back(); result.success(null) }
                    "forward" -> { tab?.forward(); result.success(null) }
                    "reload" -> { tab?.reload(); result.success(null) }
                    "stop" -> { tab?.stop(); result.success(null) }
                    "desktop" -> { tab?.setDesktop(call.argument<Boolean>("value") == true); result.success(null) }
                    "command" -> {
                        tab?.command(call.argument<String>("name") ?: "", call.argument<Map<*, *>>("args"))
                        result.success(null)
                    }
                    "close" -> { id?.let { GeckoEngine.close(it) }; result.success(null) }
                    "secure" -> { setSecure(call.argument<Boolean>("value") == true); result.success(null) }
                    "clearData" -> { GeckoEngine.clearAllData(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("GECKO", e.message, e.javaClass.simpleName)
            }
        }
        engine.platformViewsController.registry.registerViewFactory(
            "aflaak/gecko_view", GeckoViewFactory(),
        )
    }

    /** FLAG_SECURE blocks screenshots and the recents thumbnail. */
    private fun setSecure(secure: Boolean) {
        activity.runOnUiThread {
            if (secure) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}

private class GeckoViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val tabId = (args as? Map<*, *>)?.get("tabId") as? String
        return GeckoPlatformView(context, tabId?.let { GeckoEngine.tabs[it] })
    }
}

private class GeckoPlatformView(context: Context, tab: GeckoTab?) : PlatformView {
    private val geckoView = GeckoView(context)

    init {
        if (tab != null) geckoView.setSession(tab.session)
    }

    override fun getView(): View = geckoView
    override fun dispose() { geckoView.releaseSession() }
}
