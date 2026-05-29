# Soplay Backend — Mobil (Android Phone) integratsiya

Bu hujjat **soplay-backend** ni **Android mobil ilovasi** bilan ulashning to'liq qo'llanmasi. TV-ga emas, **telefon (portrait/landscape)** uchun. Asosiy diqqat: **provider-agnostic** pleyer dispatcher va anti-scraping providerlar uchun **`webview-extract`** rejimi.

> TV uchun alohida hujjat bor: `MEDIA_KOTLIN_INTEGRATION.md` (Leanback, D-pad focus, BrowseFragment va h.k.).

---

## 1. Umumiy ko'rinish

`soplay-backend` — agregator API. Turli xil saytlardan (vidapi, uzbeklar, uzmovi, frembed, anikai, ...) video stream'larini yig'ib, **bir xil JSON shaklida** mobil ilovaga qaytaradi.

Mobil ilova **3 ta narsani biladi**:
1. **`provider`** — qaysi catalog (analytics/UI uchungina)
2. **`contentUrl`** — kontent kanonik URL'i
3. **`mediaRef`** — bitta epizod uchun yagona identifikator

Pleyer mantiqida **hech qachon `provider` nomi ishlatilmaydi** — faqat `media.type` ga qarab dispatch qilinadi.

---

## 2. Oqim ketma-ketligi

```
[1] /api/contents/detail?url=<contentUrl>&provider=<name>
        ↓ (title, banner, isSerial, extra.tmdbId/anilistId, ...)
[2] /api/contents/episodes?url=<contentUrl>&provider=<name>&page=1
        ↓ (har bir epizod uchun mediaRef)
[3] /api/contents/media?ref=<mediaRef>&provider=<name>
        ↓ (videoUrl, type, headers, extractor?, videoSources[])
[4] /api/contents/subtitles?id=<imdb/tmdbId>&type=movie&language=en   (ixtiyoriy)
```

> Film (`isSerial=false`) bo'lsa `/episodes` ham bitta `mediaRef` qaytaradi.

---

## 3. Pleyer rejimlari (response `type` field)

Backend mobilga 4 xil rejim qaytarishi mumkin:

| `type` | Mobil nima qiladi | + / − |
|---|---|---|
| `hls` | Media3 `HlsMediaSource`, `headers` bilan | + Native, eng silliq |
| `mp4` | Media3 `ProgressiveMediaSource` | + Native |
| `iframe` | Ko'rinadigan WebView'da sahifani ochish | − Reklama, foydalanuvchi sahifaning o'zini ko'radi |
| `webview-extract` | **Yashirin** WebView'da sahifaning JS'i stream URL'ni hisoblaganini intercept qilib, native Media3'da o'ynatish | + Server yengil, + Reklama yo'q, native UX, − ~3 sek init |
| (noma'lum) | `iframe` fallback (forward-compat) | App crash bo'lmasin |

### 3.1 `webview-extract` — anti-scraping providerlar uchun

Ba'zi saytlar (hozircha `uzmovi`, kelajakda boshqalar ham) stream URL va auth header'larini obfuscatsiyali JS orqali runtime'da hisoblaydi. Server ularni replicate qila olmaydi. Bunday hollarda backend `type: "webview-extract"` qaytaradi va **mobilga extractor config beradi**:

```json
{
  "provider":  "uzmovi",
  "videoUrl":  "https://uzmovi.net/drama/8691-...html",
  "type":      "webview-extract",
  "headers":   { "Referer": "https://uzmovi.net/" },
  "extractor": {
    "mode":            "shouldInterceptRequest",
    "hostPattern":     "*.uzdown.space",
    "urlPatterns":     [".m3u8", ".mpd"],
    "captureHeaders":  ["X-ATT-DeviceId", "X-Match", "X-Path", "Origin", "Referer"],
    "timeoutMs":       20000,
    "loginUrl":        "https://uzmovi.net/user/login",
    "playType":        "hls"
  }
}
```

**Mobil algoritmi (bir martalik, har qanday provider uchun):**

1. **Invisible WebView yarat** (`visibility=GONE` yoki `0x0 px` Compose'da)
2. `videoUrl` ni yukla
3. `WebViewClient.shouldInterceptRequest` da har bir HTTP so'rovni tekshir:
   - Host `hostPattern` ga mos (`*.uzdown.space` → har qanday subdomain)
   - URL'da `urlPatterns` dan biri (`.m3u8` yoki `.mpd`)
4. Mos kelsa → `request.requestHeaders` dan `captureHeaders` nomli headerlarni nusxa ol
5. WebView'ni `destroy()` qil
6. Ushlangan URL + headerlarni **Media3 ExoPlayer** ga ber (`playType: "hls"` → `HlsMediaSource`)
7. **`timeoutMs` ichida ushlanmasa**:
   - `loginUrl != null` bo'lsa → WebView'ni ko'rsat va `loginUrl` ga o'tkaz (login flow)
   - Aks holda → `iframe` fallback (sahifani oddiy WebView'da ko'rsat)

> **Muhim:** mobil bu config'ni o'qib **dinamik** ishlaydi. Ertaga `frembed` ham `webview-extract` qaytarsa, `hostPattern` ni boshqasiga moslab — mobil **hech qanday yangilanmasdan** ishlatadi.

---

## 4. Gradle (`build.gradle.kts` — module)

```kotlin
plugins {
    kotlin("plugin.serialization") version "2.0.20"
}

dependencies {
    // HTTP
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.jakewharton.retrofit:retrofit2-kotlinx-serialization-converter:1.0.0")

    // Media3 (ExoPlayer)
    val media3 = "1.4.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    implementation("androidx.media3:media3-datasource-okhttp:$media3")
    implementation("androidx.media3:media3-session:$media3")          // notif/PiP uchun

    // Coroutines + Lifecycle
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.4")

    // (ixtiyoriy) Jetpack Compose
    implementation(platform("androidx.compose:compose-bom:2024.09.02"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.2")
}
```

---

## 5. JSON data classes

```kotlin
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class MediaResponse(
    val provider: String,
    val videoUrl: String? = null,
    val type: String? = null,                   // "hls" | "mp4" | "iframe" | "webview-extract"
    val headers: Map<String, String> = emptyMap(),
    val videoSources: List<VideoSource> = emptyList(),
    val subtitles: List<Subtitle> = emptyList(),
    val languagesAvailable: List<String> = emptyList(),
    val extractor: ExtractorConfig? = null      // type=webview-extract'da to'ladi
)

@Serializable
data class VideoSource(
    val quality: String = "auto",
    val videoUrl: String,
    val isDefault: Boolean = false,
    val type: String? = null,
    val host: String? = null,
    val headers: Map<String, String> = emptyMap()
)

@Serializable
data class ExtractorConfig(
    val mode: String = "shouldInterceptRequest",
    val hostPattern: String,                    // "*.uzdown.space"
    val urlPatterns: List<String>,              // [".m3u8", ".mpd"]
    val captureHeaders: List<String> = emptyList(),
    val timeoutMs: Long = 20_000,
    val loginUrl: String? = null,
    val playType: String = "hls"                // "hls" | "mp4"
)

@Serializable
data class Subtitle(val lang: String, val label: String, val url: String)

@Serializable
data class DetailResponse(
    val provider: String,
    val contentId: String? = null,
    val contentUrl: String? = null,
    val title: String,
    val description: String? = null,
    val thumbnail: String? = null,
    val banner: String? = null,
    val year: Int? = null,
    val isSerial: Boolean = false,
    val genres: List<String> = emptyList(),
    val extra: Map<String, kotlinx.serialization.json.JsonElement> = emptyMap()
)

@Serializable
data class EpisodesResponse(
    val provider: String,
    val contentUrl: String? = null,
    val isSerial: Boolean,
    val episodes: List<Episode> = emptyList(),
    val page: Int = 1,
    val size: Int = 100,
    val total: Int = 0,
    val totalPages: Int = 1
)

@Serializable
data class Episode(
    val episode: Int,
    val label: String,
    val mediaRef: String? = null,
    val availableLangs: List<String> = emptyList(),
    val image: String? = null,
    val airdate: String? = null,
    val overview: String? = null
)
```

---

## 6. Retrofit setup

```kotlin
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.GET
import retrofit2.http.Query
import java.io.File
import java.util.concurrent.TimeUnit

interface SoplayApi {
    @GET("api/contents/detail")
    suspend fun getDetail(@Query("url") url: String, @Query("provider") provider: String): DetailResponse

    @GET("api/contents/episodes")
    suspend fun getEpisodes(
        @Query("url") url: String,
        @Query("provider") provider: String,
        @Query("page") page: Int = 1,
        @Query("size") size: Int = 100,
        @Query("sort") sort: String = "asc"
    ): EpisodesResponse

    @GET("api/contents/media")
    suspend fun getMedia(
        @Query("ref") mediaRef: String,
        @Query("provider") provider: String,
        @Query("lang") lang: String? = null,
        @Query("server") server: String? = null
    ): MediaResponse

    @GET("api/contents/subtitles")
    suspend fun getSubtitles(
        @Query("id") id: String,
        @Query("type") type: String,                // "movie" | "tv"
        @Query("language") language: String = "en",
        @Query("season") season: Int? = null,
        @Query("episode") episode: Int? = null
    ): SubtitleListResponse
}

@Serializable
data class SubtitleListResponse(val items: List<Subtitle>)

object NetworkModule {
    private val json = Json {
        ignoreUnknownKeys = true                    // backend yangi field qo'shsa app crash bo'lmasin
        coerceInputValues = true
    }

    fun create(context: Context, baseUrl: String): SoplayApi {
        val cacheDir = File(context.cacheDir, "soplay-http")
        val okHttp = OkHttpClient.Builder()
            .cache(okhttp3.Cache(cacheDir, 50L * 1024 * 1024))   // detail/episodes uchun
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .addInterceptor(HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            })
            .build()

        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(okHttp)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(SoplayApi::class.java)
    }
}
```

---

## 7. Universal player dispatcher (asosiy kod)

> **MUHIM QOIDA:** mobil pleyer mantiqida **hech qachon provider nomi qattiq kiritilmasligi** kerak. `media.type` ga qarab dispatch — `media.provider` faqat analytics/UI uchun. Backend kelajakda istalgan provider'ga `webview-extract` qaytarsa, bu kod **yangilanishsiz** ishlaydi.

### 7.1 `PlayerHost` interface

UI qatlami pleyerni ko'rsatishi uchun mavhum interfeys. Sizning `Activity` / `Fragment` / `ViewModel` bu interfeysni implement qiladi.

```kotlin
interface PlayerHost {
    /** Native Media3 player ishga tushadi (hls/mp4). */
    fun playNative(url: String, type: String, headers: Map<String, String>, subtitles: List<Subtitle> = emptyList())

    /** Sahifani ko'rinadigan WebView'da ochadi (iframe fallback). */
    fun playIframe(url: String, headers: Map<String, String> = emptyMap())

    /** Login flow: foydalanuvchiga URL'ni ko'rsat, login bo'lgach onClose chaqir. */
    fun openVisibleWebView(url: String, onClose: () -> Unit)
}
```

### 7.2 WebView extractor (universal, hech qanday provider nomini bilmaydi)

```kotlin
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.*
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

data class ExtractedStream(
    val url: String,
    val headers: Map<String, String>,
    val playType: String
)

private fun matchHost(host: String, pattern: String): Boolean {
    if (!pattern.contains("*")) return host.equals(pattern, ignoreCase = true)
    val suffix = pattern.removePrefix("*.").lowercase()
    val h = host.lowercase()
    return h == suffix || h.endsWith(".$suffix")
}

/**
 * Backend bergan `extractor` config bo'yicha invisible WebView'da
 * stream URL + auth headerlarni intercept qiladi.
 * `null` qaytaradi — extraction timeout yoki cancel bo'lsa.
 */
suspend fun extractStreamViaWebView(
    context: Context,
    pageUrl: String,
    config: ExtractorConfig,
    pageHeaders: Map<String, String>,
): ExtractedStream? = suspendCancellableCoroutine { cont ->
    val main = Handler(Looper.getMainLooper())
    var webView: WebView? = null
    var captured = false

    val cleanup = {
        main.post {
            try { webView?.stopLoading(); webView?.destroy() } catch (_: Throwable) {}
            webView = null
        }
    }

    main.post {
        webView = WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.userAgentString = pageHeaders["User-Agent"]
                ?: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 " +
                   "(KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"
            visibility = View.GONE
        }

        val timeout = Runnable {
            if (!captured) {
                cleanup()
                if (cont.isActive) cont.resume(null)
            }
        }
        main.postDelayed(timeout, config.timeoutMs)

        webView?.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest
            ): WebResourceResponse? {
                if (captured) return null

                val url  = request.url
                val host = url.host ?: return null
                if (!matchHost(host, config.hostPattern)) return null

                val urlStr = url.toString()
                if (config.urlPatterns.none { urlStr.contains(it, ignoreCase = true) }) return null

                captured = true
                main.removeCallbacks(timeout)

                val headers = buildMap<String, String> {
                    request.requestHeaders.forEach { (k, v) ->
                        if (config.captureHeaders.any { it.equals(k, ignoreCase = true) }) put(k, v)
                    }
                    // Page-level header'lar (Referer/UA) ham qo'shamiz, agar captureHeaders'da bo'lmasa
                    pageHeaders.forEach { (k, v) -> if (!containsKey(k)) put(k, v) }
                }

                cleanup()
                if (cont.isActive) cont.resume(ExtractedStream(urlStr, headers, config.playType))
                return null   // request davom etadi (ehtimol fonida) — biz allaqachon ushladik
            }
        }

        // Sahifa request'ida Referer/UA ham yuborilsin
        val initialHeaders = pageHeaders.filterKeys { k -> k.equals("Referer", true) }
        webView?.loadUrl(pageUrl, initialHeaders)
    }

    cont.invokeOnCancellation { cleanup() }
}
```

### 7.3 `playMedia` dispatcher

```kotlin
suspend fun playMedia(
    context: Context,
    media: MediaResponse,
    host: PlayerHost,
    onRetry: (suspend () -> Unit)? = null     // login bo'lgandan keyin qayta chaqirish
) {
    when (media.type) {
        "hls", "mp4" -> {
            host.playNative(
                url       = media.videoUrl ?: return host.playIframe(media.videoUrl ?: return),
                type      = media.type,
                headers   = media.headers,
                subtitles = media.subtitles
            )
        }

        "webview-extract" -> {
            val cfg = media.extractor ?: run {
                // Backend xatosi — extractor field yo'q. Iframe fallback.
                host.playIframe(media.videoUrl ?: return, media.headers)
                return
            }
            val stream = extractStreamViaWebView(
                context     = context,
                pageUrl     = media.videoUrl!!,
                config      = cfg,
                pageHeaders = media.headers
            )
            if (stream != null) {
                host.playNative(stream.url, stream.playType, stream.headers, media.subtitles)
            } else if (cfg.loginUrl != null) {
                // Birinchi marta — foydalanuvchi loginga muhtoj
                host.openVisibleWebView(cfg.loginUrl) {
                    // Login tugagach pleyerni qayta urin
                    onRetry?.let { kotlinx.coroutines.GlobalScope.launch { it() } }
                }
            } else {
                host.playIframe(media.videoUrl!!, media.headers)
            }
        }

        "iframe" -> host.playIframe(media.videoUrl ?: return, media.headers)

        // Forward-compat: backend kelajakda yangi type qo'shsa, app crash bo'lmasin
        else -> host.playIframe(media.videoUrl ?: return, media.headers)
    }
}
```

---

## 8. ExoPlayer (Media3) — `PlayerActivity` yoki Compose

### 8.1 Activity-based pleyer

```kotlin
import android.net.Uri
import androidx.fragment.app.FragmentActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.PlayerView

class PlayerActivity : FragmentActivity(), PlayerHost {

    private lateinit var playerView: PlayerView
    private var player: ExoPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)
        playerView = findViewById(R.id.player_view)
    }

    override fun playNative(
        url: String,
        type: String,
        headers: Map<String, String>,
        subtitles: List<Subtitle>
    ) {
        releasePlayer()

        val httpFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
            .setUserAgent(headers["User-Agent"] ?: "Mozilla/5.0")
            .setAllowCrossProtocolRedirects(true)

        val subConfigs = subtitles.map { s ->
            MediaItem.SubtitleConfiguration.Builder(Uri.parse(s.url))
                .setMimeType(if (s.url.endsWith(".srt", true)) MimeTypes.APPLICATION_SUBRIP else MimeTypes.TEXT_VTT)
                .setLanguage(s.lang)
                .build()
        }

        val item = MediaItem.Builder()
            .setUri(url)
            .setSubtitleConfigurations(subConfigs)
            .build()

        val source = when (type) {
            "hls" -> HlsMediaSource.Factory(httpFactory).createMediaSource(item)
            else  -> ProgressiveMediaSource.Factory(httpFactory).createMediaSource(item)
        }

        player = ExoPlayer.Builder(this).build().also {
            it.setMediaSource(source)
            it.prepare()
            it.playWhenReady = true
        }
        playerView.player = player
    }

    override fun playIframe(url: String, headers: Map<String, String>) {
        startActivity(Intent(this, IframePlayerActivity::class.java).apply {
            putExtra("url", url)
            putExtra("referer", headers["Referer"] ?: "")
        })
        finish()
    }

    override fun openVisibleWebView(url: String, onClose: () -> Unit) {
        // Login flow uchun — IframePlayerActivity'ni ko'rinadigan rejimda ochib,
        // foydalanuvchi yopgach (onBackPressed) onClose ni chaqiramiz.
        val intent = Intent(this, IframePlayerActivity::class.java)
            .putExtra("url", url)
            .putExtra("login_mode", true)
        startActivityForResult(intent, REQ_LOGIN)
        pendingLoginCallback = onClose
    }

    private var pendingLoginCallback: (() -> Unit)? = null

    @Deprecated("for sample only")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_LOGIN) pendingLoginCallback?.invoke()
        pendingLoginCallback = null
    }

    override fun onPause() {
        super.onPause()
        player?.pause()
    }

    override fun onStop() {
        super.onStop()
        releasePlayer()
    }

    private fun releasePlayer() {
        player?.release()
        player = null
        playerView.player = null
    }

    companion object { private const val REQ_LOGIN = 4242 }
}
```

### 8.2 `IframePlayerActivity` — login va fallback uchun

```kotlin
import android.os.Bundle
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.fragment.app.FragmentActivity

class IframePlayerActivity : FragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url      = intent.getStringExtra("url")!!
        val referer  = intent.getStringExtra("referer").orEmpty()
        val isLogin  = intent.getBooleanExtra("login_mode", false)

        // Cookie'larni domain bo'yicha saqlash (login session keyingi safar ishlatiladi)
        CookieManager.getInstance().setAcceptCookie(true)

        val web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.allowContentAccess = true
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            webViewClient = WebViewClient()

            val initial = if (referer.isNotBlank()) mapOf("Referer" to referer) else emptyMap()
            loadUrl(url, initial)
        }
        setContentView(web)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (web.canGoBack()) web.goBack()
                else {
                    setResult(if (isLogin) RESULT_OK else RESULT_CANCELED)
                    finish()
                }
            }
        })
    }
}
```

### 8.3 (Ixtiyoriy) Jetpack Compose pleyer

```kotlin
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.ui.PlayerView

@Composable
fun PlayerScreen(media: MediaResponse, onIframe: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var player by remember { mutableStateOf<ExoPlayer?>(null) }

    val host = remember {
        object : PlayerHost {
            override fun playNative(url: String, type: String, headers: Map<String, String>, subtitles: List<Subtitle>) {
                player?.release()
                val factory = DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)
                val item = MediaItem.fromUri(url)
                val source = if (type == "hls")
                    HlsMediaSource.Factory(factory).createMediaSource(item)
                else
                    ProgressiveMediaSource.Factory(factory).createMediaSource(item)
                player = ExoPlayer.Builder(context).build().apply {
                    setMediaSource(source); prepare(); playWhenReady = true
                }
            }
            override fun playIframe(url: String, headers: Map<String, String>) = onIframe(url)
            override fun openVisibleWebView(url: String, onClose: () -> Unit) = onIframe(url)
        }
    }

    LaunchedEffect(media) { playMedia(context, media, host) }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { PlayerView(it).apply { useController = true } },
        update = { it.player = player }
    )

    DisposableEffect(Unit) {
        onDispose { player?.release() }
    }
}
```

---

## 9. Mobil-specific maslahatlar

### 9.1 Orientation

- Pleyer Activity uchun `android:screenOrientation="sensorLandscape"` (Manifest'da). Foydalanuvchi telefonni burgan zahoti landscape'ga o'tadi.
- Yoki ichida `setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE)` qiling.

### 9.2 Lifecycle (`onPause` / `onStop` / `onResume`)

- `onPause` da `player.pause()` — telefon ekrani o'chsa pauza qiling
- `onStop` da `player.release()` — resurslarni bo'shating
- WebView extraction'da `onStop` chaqirilsa coroutine'ni `cancel` qiling — `withContext(viewModelScope.coroutineContext)` ishlating

### 9.3 PiP (Picture-in-Picture) — Android 8+

```xml
<!-- Manifest -->
<activity
    android:name=".PlayerActivity"
    android:supportsPictureInPicture="true"
    android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation"
/>
```

```kotlin
// PlayerActivity
override fun onUserLeaveHint() {
    if (player?.isPlaying == true) {
        enterPictureInPictureMode(
            PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
        )
    }
}
```

### 9.4 Background playback (`MediaSessionService`)

```kotlin
class PlaybackService : androidx.media3.session.MediaSessionService() {
    private var session: androidx.media3.session.MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val player = ExoPlayer.Builder(this).build()
        session = androidx.media3.session.MediaSession.Builder(this, player).build()
    }
    override fun onGetSession(controllerInfo: androidx.media3.session.MediaSession.ControllerInfo) = session
    override fun onDestroy() {
        session?.run { player.release(); release() }
        super.onDestroy()
    }
}
```

### 9.5 Touch controls va gestures

Media3 `PlayerView` o'zining touch controllerini beradi (qisman). Custom gesture (volume swipe, brightness swipe, double-tap to seek) uchun `GestureDetector` qo'shing yoki tayyor kutubxonadan foydalaning (masalan `media3-ui-leanback` bunda mos kelmaydi — mobile uchun custom kerak).

### 9.6 WebView extraction performance

- `extractStreamViaWebView` ~2–4 sek davom etadi (sahifa JS yuklab, stream so'rovi qilguncha)
- Foydalanuvchiga **progress indikator** ko'rsating (`CircularProgressIndicator` / "Yuklanyapti...")
- Birinchi marta sekinroq (cache yo'q), keyingi marta WebView cache'i tezroq
- `timeoutMs` ni 20s deb qoldiring — undan ko'p kutmang

### 9.7 WebView cookie persistence

`CookieManager.getInstance().setAcceptCookie(true)` — bir marta qo'ying (`Application.onCreate`'da). Bu hammasi: WebView ichida foydalanuvchi bir marta login bo'lsa, keyingi safar avtomatik ishlaydi.

```kotlin
class SoplayApp : Application() {
    override fun onCreate() {
        super.onCreate()
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().acceptThirdPartyCookies(/* webview */)
    }
}
```

---

## 10. To'liq misol — har qanday provider uchun

```kotlin
class WatchViewModel(private val api: SoplayApi) : ViewModel() {

    fun play(activity: PlayerActivity, contentUrl: String, provider: String, lang: String? = null) {
        viewModelScope.launch {
            try {
                val eps = api.getEpisodes(contentUrl, provider)
                val first = eps.episodes.firstOrNull() ?: return@launch
                val media = api.getMedia(first.mediaRef!!, provider, lang)

                // Universal dispatcher — provider nomi muhim emas
                playMedia(
                    context = activity,
                    media   = media,
                    host    = activity,
                    onRetry = {
                        // Login bo'lgach qayta urinish
                        val m2 = api.getMedia(first.mediaRef, provider, lang)
                        playMedia(activity, m2, activity)
                    }
                )
            } catch (e: Exception) {
                Toast.makeText(activity, "Xatolik: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }
}
```

Foydalanish:

```kotlin
// Anikai (hls) — playNative chaqiriladi
viewModel.play(this, "https://www1.anikai.cc/watch/naruto", provider = "anikai", lang = "sub")

// Uzmovi (webview-extract) — invisible WebView orqali extract va playNative
viewModel.play(this, "https://uzmovi.net/.../film.html", provider = "uzmovi")

// Uzbeklar (mp4) — playNative
viewModel.play(this, "https://uzbeklar.biz/.../film.html", provider = "uzbeklar")

// Frembed (iframe) — playIframe
viewModel.play(this, "https://www.themoviedb.org/movie/12345", provider = "frembed")
```

Mobil kodga **bitta o'zgartirish** kerak emas — barchasi `media.type` ga qarab avtomatik dispatch.

---

## 11. Diagnostika

| Muammo | Sabab | Yechim |
|---|---|---|
| `webview-extract` doim `null` qaytaradi | `hostPattern` mos kelmayapti yoki sahifada login yo'q | Logcat'da `shouldInterceptRequest` ga keladi URL'larni log qiling |
| Stream 403 keladi | Headerlardan biri qo'lga olinmagan | `extractor.captureHeaders` ro'yxatini tekshiring, kerak bo'lsa backendga qo'shing |
| Player kara ekran | `headers["Referer"]` ulanmagan | `DefaultHttpDataSource.Factory.setDefaultRequestProperties(headers)` chaqirganingizni tekshiring |
| Login WebView yopilgandan keyin player ishga tushmadi | `onRetry` callback'i ulanmagan | `playMedia(... onRetry = { ... })` parametr berdingizmi? |
| Subtitle ko'rinmayapti | Mimetype noto'g'ri | `.srt` → `MimeTypes.APPLICATION_SUBRIP`, `.vtt` → `MimeTypes.TEXT_VTT` |
| Noma'lum `type` keldi | Backend yangi rejim qo'shdi | `else` branch'da `playIframe` fallback bor — app crash bo'lmaydi, lekin docs'ni yangilang |

---

## 12. Qoidalar (mobil dasturchi uchun)

- ✅ `media.type` ga qarab dispatch qiling — **`media.provider` ga emas**
- ✅ Noma'lum `type` kelsa — `iframe` fallback (forward-compat)
- ✅ `extractor.hostPattern`, `urlPatterns`, `captureHeaders` ni backend'dan o'qib dinamik ishlating — qattiq kiritmang
- ✅ `extractor.timeoutMs` ga rioya qiling
- ✅ WebView lifecycle'ni boshqaring (`onStop` da `destroy()`)
- ✅ `CookieManager.setAcceptCookie(true)` — Application'da bir marta
- ❌ **Hech qachon** `if (provider == "uzmovi") ...` deb yozmang. Bu pattern eski (TV) docs'da xato bilan bo'lgan — endi rad etilgan
- ❌ Stream URL pattern'larini (`*.uzdown.space`, `*.m3u8`) mobilda hard-code qilmang — backend yuboradi
- ❌ Provider muvaffaqiyatsiz bo'lsa app crash bo'lmasin — `try/catch` + `playIframe` fallback
- ❌ `extractor` field'ini noma'lum providerlardan kutmang — `null` bo'lishi normal

---

## Xulosa

- **3 ta endpoint**: `/detail` → `/episodes` → `/media`
- **4 ta `type`**: `hls`, `mp4`, `iframe`, `webview-extract` — kelajakda yana qo'shilishi mumkin
- **1 ta dispatcher**: `playMedia(...)` — barcha provider va type uchun
- **1 ta extractor**: `extractStreamViaWebView(...)` — backend bergan config bo'yicha dinamik
- **Forward-compat**: noma'lum type → iframe fallback, app crash bo'lmaydi
- **Provider-agnostic**: yangi provider qo'shilsa mobil yangilanish kerak emas
