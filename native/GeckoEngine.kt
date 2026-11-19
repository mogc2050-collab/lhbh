package com.ibetoo.ibetoo_media

import android.content.Context
import android.util.Log
import org.json.JSONObject
import org.mozilla.geckoview.ContentBlocking
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.WebExtension
import org.mozilla.geckoview.WebResponse
import org.mozilla.geckoview.WebRequestError
import java.util.UUID

private const val TAG = "AflaakGecko"
const val CORE_EXTENSION_ID = "aflaak-core@aflaak.com"
const val CORE_NATIVE_APP = "aflaak"
private const val CORE_URI = "resource://android/assets/web_extensions/aflaak-core/"
private const val UBLOCK_ID = "uBlock0@raymondhill.net"
private const val UBLOCK_URI = "resource://android/assets/web_extensions/ublock-origin/"

/** Receives engine events and forwards them to Flutter. */
fun interface TabEventSink { fun emit(event: Map<String, Any?>) }

/**
 * Application-scoped GeckoRuntime plus the registry of live tabs.
 * Exactly one GeckoRuntime may exist per process.
 */
object GeckoEngine {
    private var runtimeInstance: GeckoRuntime? = null
    private var core: WebExtension? = null
    val tabs = LinkedHashMap<String, GeckoTab>()
    var sink: TabEventSink? = null

    @Synchronized
    fun runtime(context: Context): GeckoRuntime {
        runtimeInstance?.let { return it }
        val app = context.applicationContext
        val blocking = ContentBlocking.Settings.Builder()
            .antiTracking(ContentBlocking.AntiTracking.DEFAULT)
            .safeBrowsing(ContentBlocking.SafeBrowsing.DEFAULT)
            .cookieBehavior(ContentBlocking.CookieBehavior.ACCEPT_FIRST_PARTY_AND_ISOLATE_OTHERS)
            .enhancedTrackingProtectionLevel(ContentBlocking.EtpLevel.DEFAULT)
            .build()
        val settings = GeckoRuntimeSettings.Builder()
            .javaScriptEnabled(true)
            .remoteDebuggingEnabled(false)
            .consoleOutput(false)
            .aboutConfigEnabled(false)
            .allowInsecureConnections(GeckoRuntimeSettings.HTTPS_ONLY)
            .contentBlocking(blocking)
            .build()
        val created = GeckoRuntime.create(app, settings)
        runtimeInstance = created
        installExtensions(created, app)
        return created
    }

    private fun installExtensions(runtime: GeckoRuntime, context: Context) {
        val controller = runtime.webExtensionController
        controller.ensureBuiltIn(CORE_URI, CORE_EXTENSION_ID).accept(
            { ext ->
                if (ext != null) {
                    core = ext
                    controller.setAllowedInPrivateBrowsing(ext, true)
                    tabs.values.forEach { it.attachCore(ext) }
                }
            },
            { error -> Log.e(TAG, "aflaak-core failed to load", error) },
        )
        // uBlock Origin is optional: CI unpacks it into assets when available.
        val hasUblock = try {
            context.assets.list("web_extensions/ublock-origin")?.isNotEmpty() == true
        } catch (e: Exception) { false }
        if (hasUblock) {
            controller.ensureBuiltIn(UBLOCK_URI, UBLOCK_ID).accept(
                { ext -> if (ext != null) controller.setAllowedInPrivateBrowsing(ext, true) },
                { error -> Log.e(TAG, "uBlock Origin failed to load", error) },
            )
        } else {
            Log.w(TAG, "uBlock Origin not bundled in assets")
        }
    }

    fun coreExtension(): WebExtension? = core

    fun create(
        context: Context, tabId: String, private: Boolean, containerId: String?,
        prompts: GeckoSession.PromptDelegate?,
    ): GeckoTab {
        val runtime = runtime(context)
        // Private tabs get their own random contextId so cookies, storage and
        // cache are isolated from every other session and from each other.
        val contextId = when {
            private -> "p" + UUID.randomUUID().toString().replace("-", "")
            !containerId.isNullOrBlank() -> "c" + containerId.filter { it.isLetterOrDigit() }
            else -> null
        }
        val tab = GeckoTab(runtime, tabId, private, contextId, prompts)
        tabs[tabId] = tab
        core?.let { tab.attachCore(it) }
        return tab
    }

    fun close(tabId: String) {
        val tab = tabs.remove(tabId) ?: return
        tab.dispose()
        val ctx = tab.contextId
        val runtime = runtimeInstance
        if (tab.private && ctx != null && runtime != null) {
            runtime.storageController.clearDataForSessionContext(ctx)
        }
    }

    fun clearAllData() {
        runtimeInstance?.storageController?.clearData(
            org.mozilla.geckoview.StorageController.ClearFlags.ALL,
        )
    }
}

class GeckoTab(
    private val runtime: GeckoRuntime,
    val id: String,
    val private: Boolean,
    val contextId: String?,
    prompts: GeckoSession.PromptDelegate?,
) {
    val session: GeckoSession
    private var lastUrl = ""
    private var desktop = false
    private var dark = false
    private var port: WebExtension.Port? = null
    private var canBack = false
    private var canFwd = false

    private fun emit(type: String, vararg pairs: Pair<String, Any?>) {
        val map = HashMap<String, Any?>()
        map["tabId"] = id
        map["type"] = type
        pairs.forEach { map[it.first] = it.second }
        GeckoEngine.sink?.emit(map)
    }

    fun load(url: String) { lastUrl = url; session.loadUri(url) }
    fun back() = session.goBack()
    fun forward() = session.goForward()
    fun reload() = session.reload()
    fun stop() = session.stop()

    fun setDesktop(value: Boolean) {
        desktop = value
        session.settings.userAgentMode =
            if (value) GeckoSessionSettings.USER_AGENT_MODE_DESKTOP
            else GeckoSessionSettings.USER_AGENT_MODE_MOBILE
        session.settings.viewportMode =
            if (value) GeckoSessionSettings.VIEWPORT_MODE_DESKTOP
            else GeckoSessionSettings.VIEWPORT_MODE_MOBILE
        session.reload()
    }

    /** Sends a command to the aflaak-core content script of this tab. */
    fun command(name: String, args: Map<*, *>?) {
        if (name == "dark") dark = args?.get("on") == true
        val p = port ?: return
        try {
            val payload = JSONObject().put("cmd", name)
            val a = JSONObject()
            args?.forEach { (k, v) -> if (k is String) a.put(k, v) }
            p.postMessage(payload.put("args", a))
        } catch (e: Exception) {
            Log.w(TAG, "command $name failed", e)
        }
    }

    fun attachCore(ext: WebExtension) {
        session.webExtensionController.setMessageDelegate(ext, messages, CORE_NATIVE_APP)
    }

    fun dispose() {
        port = null
        session.close()
    }

    private val messages = object : WebExtension.MessageDelegate {
        override fun onConnect(connected: WebExtension.Port) {
            port = connected
            connected.setDelegate(object : WebExtension.PortDelegate {
                override fun onPortMessage(message: Any, source: WebExtension.Port) {}
                override fun onDisconnect(source: WebExtension.Port) {
                    if (port === source) port = null
                }
            })
            // Re-apply persistent per-tab state on every page load.
            if (dark) command("dark", mapOf("on" to true))
        }
    }

    private val navigation = object : GeckoSession.NavigationDelegate {
        override fun onLocationChange(
            session: GeckoSession,
            url: String?,
            perms: MutableList<GeckoSession.PermissionDelegate.ContentPermission>,
            hasUserGesture: Boolean,
        ) {
            lastUrl = url ?: lastUrl
            emit("location", "url" to url)
        }

        override fun onCanGoBack(session: GeckoSession, canGoBack: Boolean) {
            canBack = canGoBack
            emit("history", "back" to canBack, "forward" to canFwd)
        }

        override fun onCanGoForward(session: GeckoSession, canGoForward: Boolean) {
            canFwd = canGoForward
            emit("history", "back" to canBack, "forward" to canFwd)
        }

        override fun onLoadRequest(
            session: GeckoSession,
            request: GeckoSession.NavigationDelegate.LoadRequest,
        ): GeckoResult<org.mozilla.geckoview.AllowOrDeny>? {
            val uri = request.uri
            val scheme = uri.substringBefore(':', "").lowercase()
            val allowed = scheme in setOf("https", "http", "about", "blob", "data", "view-source")
            if (!allowed) {
                if (scheme.isNotEmpty() && scheme != "javascript" && scheme != "file") {
                    emit("external", "url" to uri)
                }
                return GeckoResult.fromValue(org.mozilla.geckoview.AllowOrDeny.DENY)
            }
            return GeckoResult.fromValue(org.mozilla.geckoview.AllowOrDeny.ALLOW)
        }

        override fun onNewSession(session: GeckoSession, uri: String): GeckoResult<GeckoSession>? {
            // Popups open as a normal Flutter-managed tab instead.
            emit("newTab", "url" to uri)
            return null
        }

        override fun onLoadError(
            session: GeckoSession, uri: String?, error: WebRequestError,
        ): GeckoResult<String>? {
            emit("error", "uri" to uri, "message" to "Error ${error.code} (${error.category})")
            return null
        }
    }

    private val progress = object : GeckoSession.ProgressDelegate {
        override fun onPageStart(session: GeckoSession, url: String) {
            emit("pageStart", "url" to url)
        }

        override fun onPageStop(session: GeckoSession, success: Boolean) {
            emit("pageStop", "success" to success)
        }

        override fun onProgressChange(session: GeckoSession, progress: Int) {
            emit("progress", "value" to progress)
        }
    }

    private val content = object : GeckoSession.ContentDelegate {
        override fun onTitleChange(session: GeckoSession, title: String?) {
            emit("title", "title" to (title ?: ""))
        }

        override fun onFullScreen(session: GeckoSession, fullScreen: Boolean) {
            emit("fullscreen", "value" to fullScreen)
        }

        override fun onExternalResponse(session: GeckoSession, response: WebResponse) {
            emit("download", "url" to response.uri)
        }

        override fun onCrash(session: GeckoSession) {
            emit("crash")
            session.open(runtime)
            if (lastUrl.isNotEmpty()) session.loadUri(lastUrl)
        }

        override fun onKill(session: GeckoSession) {
            emit("crash")
            session.open(runtime)
            if (lastUrl.isNotEmpty()) session.loadUri(lastUrl)
        }
    }

    init {
        val builder = GeckoSessionSettings.Builder().usePrivateMode(private)
        if (contextId != null) builder.contextId(contextId)
        session = try {
            GeckoSession(builder.build())
        } catch (e: Exception) {
            // Fall back to private mode without a context if the engine
            // rejects the combination.
            Log.e(TAG, "contextId rejected, falling back", e)
            GeckoSession(GeckoSessionSettings.Builder().usePrivateMode(private).build())
        }
        session.navigationDelegate = navigation
        session.progressDelegate = progress
        session.contentDelegate = content
        if (prompts != null) session.promptDelegate = prompts
        session.open(runtime)
    }
}
