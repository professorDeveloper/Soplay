package com.soplay.sozo

import android.Manifest
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.media.AudioManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import kotlin.math.roundToInt
import com.soplay.sozo.cloudstream.PluginHost
import com.soplay.sozo.cloudstream.RepoManager
import com.soplay.sozo.aniyomi.AniyomiHost
import com.soplay.sozo.aniyomi.AniyomiRepoManager
import com.soplay.sozo.preview.FramePreview
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterFragmentActivity() {

    private val channelName = "soplay/pip"
    private val downloadChannelName = "soplay/downloads"
    private val systemControlsChannelName = "soplay/system_controls"
    private val deeplinkSettingsChannelName = "soplay/deeplink_settings"
    private val actionBroadcastName = "com.soplay.sozo.PIP_ACTION"
    private val actionExtraId = "action_id"

    private var methodChannel: MethodChannel? = null
    private var downloadChannel: MethodChannel? = null
    private var systemControlsChannel: MethodChannel? = null
    private var deeplinkSettingsChannel: MethodChannel? = null
    private var pipReceiver: BroadcastReceiver? = null
    private var notificationPermissionResult: MethodChannel.Result? = null

    // CloudStream plugin host (Android-only feature). Lazy so the runtime only
    // spins up if the feature is used.
    private val cloudstreamChannelName = "soplay/cloudstream"
    private var cloudstreamChannel: MethodChannel? = null
    private var previewChannel: MethodChannel? = null
    private val cloudstreamScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val pluginHost by lazy { PluginHost(applicationContext) }
    private val repoManager by lazy { RepoManager(applicationContext, pluginHost) }

    private val aniyomiChannelName = "soplay/aniyomi"
    private var aniyomiChannel: MethodChannel? = null
    private val aniyomiHost by lazy { AniyomiHost(applicationContext) }
    private val aniyomiRepoManager by lazy { AniyomiRepoManager(applicationContext, aniyomiHost) }

    companion object {
        const val ACTION_PLAY_PAUSE = "play_pause"
        const val ACTION_REWIND = "rewind"
        const val ACTION_FORWARD = "forward"
        const val ACTION_PREV = "prev"
        const val ACTION_NEXT = "next"

        const val REQ_PLAY_PAUSE = 1
        const val REQ_REWIND = 2
        const val REQ_FORWARD = 3
        const val REQ_PREV = 4
        const val REQ_NEXT = 5
        const val REQ_NOTIFICATIONS = 42
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updatePiPActions" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val hasPrev = call.argument<Boolean>("hasPrev") ?: false
                    val hasNext = call.argument<Boolean>("hasNext") ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        applyPipActions(isPlaying, hasPrev, hasNext)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        downloadChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            downloadChannelName
        )
        downloadChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "startDownload" -> {
                    val id = call.argument<String>("id").orEmpty()
                    val title = call.argument<String>("title").orEmpty()
                    val url = call.argument<String>("url").orEmpty()
                    val localPath = call.argument<String>("localPath").orEmpty()
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    if (id.isEmpty() || url.isEmpty() || localPath.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, DownloadForegroundService::class.java)
                        .setAction(DownloadForegroundService.ACTION_START)
                        .putExtra(DownloadForegroundService.EXTRA_ID, id)
                        .putExtra(DownloadForegroundService.EXTRA_TITLE, title)
                        .putExtra(DownloadForegroundService.EXTRA_URL, url)
                        .putExtra(DownloadForegroundService.EXTRA_LOCAL_PATH, localPath)
                        .putExtra(
                            DownloadForegroundService.EXTRA_HEADERS_JSON,
                            JSONObject(headers).toString()
                        )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "getDownloadStates" -> {
                    result.success(DownloadForegroundService.readStates(this))
                }
                "cancelDownload" -> {
                    val id = call.argument<String>("id").orEmpty()
                    startService(
                        Intent(this, DownloadForegroundService::class.java)
                            .setAction(DownloadForegroundService.ACTION_CANCEL)
                            .putExtra(DownloadForegroundService.EXTRA_ID, id)
                    )
                    result.success(null)
                }
                "removeDownloadState" -> {
                    val id = call.argument<String>("id").orEmpty()
                    DownloadForegroundService.removeState(this, id)
                    result.success(null)
                }
                "cancelAllDownloads" -> {
                    startService(
                        Intent(this, DownloadForegroundService::class.java)
                            .setAction(DownloadForegroundService.ACTION_CANCEL_ALL)
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        systemControlsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            systemControlsChannelName
        )
        systemControlsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getVolume" -> result.success(getMusicVolume())
                "setVolume" -> {
                    val value = call.argument<Number>("value")?.toDouble() ?: 1.0
                    setMusicVolume(value)
                    result.success(getMusicVolume())
                }
                "getBrightness" -> result.success(getWindowBrightness())
                "setBrightness" -> {
                    val value = call.argument<Number>("value")?.toDouble() ?: 0.5
                    setWindowBrightness(value)
                    result.success(getWindowBrightness())
                }
                "resetBrightness" -> {
                    resetWindowBrightness()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        deeplinkSettingsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deeplinkSettingsChannelName
        )
        deeplinkSettingsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openDefaultLinksSettings" -> {
                    result.success(openDefaultLinksSettings())
                }
                else -> result.notImplemented()
            }
        }

        cloudstreamChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            cloudstreamChannelName
        )
        cloudstreamChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "listProviders" -> result.success(pluginHost.providersJson())
                "ensureLoaded" -> csAsync(result) {
                    repoManager.ensureLoaded(); pluginHost.providersJson()
                }
                "listRepos" -> result.success(repoManager.listReposJson())
                "removeRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    result.success(repoManager.removeRepo(url))
                }
                "addRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) {
                        repoManager.addRepo(url) { current, total ->
                            // Push live "N / M installed" to the Flutter install UI.
                            runOnUiThread {
                                cloudstreamChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                "getMainPage" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { pluginHost.getMainPageJson(provider, page) }
                }
                "getGenres" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    csAsync(result) { pluginHost.getGenresJson(provider) }
                }
                "getSection" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val data = call.argument<String>("data").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    csAsync(result) { pluginHost.getSectionJson(provider, data, page) }
                }
                "search" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val query = call.argument<String>("query").orEmpty()
                    csAsync(result) { pluginHost.searchJson(provider, query) }
                }
                "load" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) { pluginHost.loadJson(provider, url) }
                }
                "loadLinks" -> {
                    val provider = call.argument<String>("provider").orEmpty()
                    val data = call.argument<String>("data").orEmpty()
                    csAsync(result) { pluginHost.loadLinksJson(provider, data) }
                }
                else -> result.notImplemented()
            }
        }

        aniyomiChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            aniyomiChannelName
        )
        aniyomiChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "listProviders" -> result.success(aniyomiHost.providersJson())
                "ensureLoaded" -> csAsync(result) {
                    aniyomiRepoManager.ensureLoaded(); aniyomiHost.providersJson()
                }
                "listRepos" -> result.success(aniyomiRepoManager.listReposJson())
                "removeRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    result.success(aniyomiRepoManager.removeRepo(url))
                }
                "addRepo" -> {
                    val url = call.argument<String>("url").orEmpty()
                    csAsync(result) {
                        aniyomiRepoManager.addRepo(url) { current, total ->
                            runOnUiThread {
                                aniyomiChannel?.invokeMethod(
                                    "installProgress",
                                    mapOf("current" to current, "total" to total),
                                )
                            }
                        }.toString()
                    }
                }
                else -> result.notImplemented()
            }
        }

        previewChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soplay/preview",
        )
        previewChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val warmMs = (call.argument<Number>("warmMs") ?: -1).toLong()
                    cloudstreamScope.launch {
                        FramePreview.open(url, headers, warmMs)
                        withContext(Dispatchers.Main) { result.success(true) }
                    }
                }
                "frame" -> {
                    val posMs = (call.argument<Number>("posMs") ?: 0).toLong()
                    cloudstreamScope.launch {
                        val bytes = FramePreview.frame(posMs)
                        withContext(Dispatchers.Main) { result.success(bytes) }
                    }
                }
                "close" -> { FramePreview.close(); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    /** Run a suspend CloudStream call off the main thread, return JSON to Flutter. */
    private fun csAsync(result: MethodChannel.Result, block: suspend () -> String) {
        cloudstreamScope.launch {
            val out = try { block() } catch (t: Throwable) { null }
            withContext(Dispatchers.Main) {
                if (out != null) result.success(out)
                else result.error("cs_error", "CloudStream call failed", null)
            }
        }
    }

    private fun openDefaultLinksSettings(): Boolean {
        val pkgUri = Uri.parse("package:$packageName")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val intent = Intent(
                    Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS,
                    pkgUri
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return try {
            val fallback = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                pkgUri
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(fallback)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun getMusicVolume(): Double {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        return current.toDouble() / max.toDouble()
    }

    private fun setMusicVolume(value: Double) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val level = (value.coerceIn(0.0, 1.0) * max).roundToInt().coerceIn(0, max)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, level, 0)
    }

    private fun getWindowBrightness(): Double {
        val windowValue = window.attributes.screenBrightness
        if (windowValue >= 0f) return windowValue.toDouble().coerceIn(0.0, 1.0)
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                .toDouble()
                .div(255.0)
                .coerceIn(0.0, 1.0)
        } catch (_: Exception) {
            0.5
        }
    }

    private fun setWindowBrightness(value: Double) {
        runOnUiThread {
            val attrs = window.attributes
            attrs.screenBrightness = value.coerceIn(0.01, 1.0).toFloat()
            window.attributes = attrs
        }
    }

    private fun resetWindowBrightness() {
        runOnUiThread {
            val attrs = window.attributes
            attrs.screenBrightness = -1f
            window.attributes = attrs
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.success(false)
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_NOTIFICATIONS
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun applyPipActions(
        isPlaying: Boolean,
        hasPrev: Boolean,
        hasNext: Boolean
    ) {
        val actions = mutableListOf<RemoteAction>()

        if (hasPrev) {
            actions.add(
                makeAction(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    "Previous episode",
                    ACTION_PREV,
                    REQ_PREV
                )
            )
        }
        actions.add(
            makeAction(
                android.R.drawable.ic_media_rew,
                "Rewind 10",
                "Rewind 10 seconds",
                ACTION_REWIND,
                REQ_REWIND
            )
        )
        actions.add(
            makeAction(
                if (isPlaying)
                    android.R.drawable.ic_media_pause
                else
                    android.R.drawable.ic_media_play,
                if (isPlaying) "Pause" else "Play",
                if (isPlaying) "Pause" else "Play",
                ACTION_PLAY_PAUSE,
                REQ_PLAY_PAUSE
            )
        )
        actions.add(
            makeAction(
                android.R.drawable.ic_media_ff,
                "Forward 10",
                "Forward 10 seconds",
                ACTION_FORWARD,
                REQ_FORWARD
            )
        )
        if (hasNext) {
            actions.add(
                makeAction(
                    android.R.drawable.ic_media_next,
                    "Next",
                    "Next episode",
                    ACTION_NEXT,
                    REQ_NEXT
                )
            )
        }

        val params = PictureInPictureParams.Builder()
            .setActions(actions)
            .build()

        try {
            setPictureInPictureParams(params)
        } catch (_: Exception) {
            // Activity may not be in a state to receive PiP params yet
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun makeAction(
        iconRes: Int,
        title: String,
        contentDesc: String,
        actionId: String,
        requestCode: Int
    ): RemoteAction {
        val intent = Intent(actionBroadcastName)
            .setPackage(packageName)
            .putExtra(actionExtraId, actionId)
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            else
                PendingIntent.FLAG_UPDATE_CURRENT
        val pending = PendingIntent.getBroadcast(this, requestCode, intent, flags)
        val icon = Icon.createWithResource(this, iconRes)
        return RemoteAction(icon, title, contentDesc, pending)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerPipReceiver()
    }

    private fun registerPipReceiver() {
        if (pipReceiver != null) return
        pipReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != actionBroadcastName) return
                val actionId = intent.getStringExtra(actionExtraId) ?: return
                methodChannel?.invokeMethod("onPipAction", actionId)
            }
        }
        val filter = IntentFilter(actionBroadcastName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(pipReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        pipReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
            pipReceiver = null
        }
    }
}
