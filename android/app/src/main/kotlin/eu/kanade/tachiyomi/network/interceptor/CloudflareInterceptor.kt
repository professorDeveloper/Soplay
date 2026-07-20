package eu.kanade.tachiyomi.network.interceptor

import android.annotation.SuppressLint
import android.content.Context
import android.os.SystemClock
import android.webkit.WebView
import android.widget.Toast
import androidx.core.content.ContextCompat
import eu.kanade.tachiyomi.network.AndroidCookieJar
import eu.kanade.tachiyomi.util.system.WebViewClientCompat
import eu.kanade.tachiyomi.util.system.isOutdated
import eu.kanade.tachiyomi.util.system.toast
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch

class CloudflareInterceptor(
    private val context: Context,
    private val cookieManager: AndroidCookieJar,
    defaultUserAgentProvider: () -> String,
) : WebViewInterceptor(context, defaultUserAgentProvider) {

    private val executor = ContextCompat.getMainExecutor(context)

    /** Per-host solve mutexes, so one gated source can't stall every other. */
    private val hostLocks = ConcurrentHashMap<String, Any>()

    /** host → elapsedRealtime of its last successful solve. */
    private val lastSolvedAt = ConcurrentHashMap<String, Long>()

    override fun shouldIntercept(response: Response): Boolean {
        // Check if Cloudflare anti-bot is on
        return response.code in ERROR_CODES && response.header("Server") in SERVER_CHECK
    }

    /**
     * Runs the WebView challenge for [request] and returns once a fresh
     * `cf_clearance` is in the system cookie store, or throws [IOException].
     *
     * Exists for callers that are not inside this interceptor's own chain —
     * specifically [com.lagradost.cloudstream3.network.CloudflareKiller], which
     * CloudStream plugins install on their own OkHttp clients. Those clients do
     * not share our cookie jar, so they need to drive the solve themselves and
     * then attach the cookies by hand; without this they would each need a
     * duplicate copy of the WebView dance below.
     */
    fun solveChallenge(request: Request) {
        try {
            solveOncePerHost(request)
        } catch (e: CloudflareBypassException) {
            throw IOException("Failed to bypass Cloudflare")
        } catch (e: Exception) {
            throw IOException(e)
        }
    }

    /**
     * Serialises solves per host, and skips the solve entirely if another thread
     * just produced a clearance cookie for it.
     *
     * Without this, two concurrent requests to the same gated host destroy each
     * other: the solve begins by *deleting* `cf_clearance` from the global
     * WebView cookie store, so thread B's delete wipes the cookie thread A just
     * earned, and both end up throwing. MangaHost issues getPopular and
     * getLatest concurrently — and details+chapters+related as three — so on a
     * Cloudflare-gated source this was close to guaranteed.
     *
     * Locking per host rather than globally keeps unrelated sources from
     * queueing behind a 30-second solve.
     */
    private fun solveOncePerHost(request: Request) {
        val host = request.url.host
        val lock = hostLocks.getOrPut(host) { Any() }
        synchronized(lock) {
            // Was this host solved moments ago by whoever held the lock before
            // us? Then our 403 was already in flight when that solve landed, and
            // re-solving would just throw the fresh cookie away.
            //
            // The window is what distinguishes "someone just fixed this" from
            // "the stored cookie genuinely stopped working" — an expired
            // clearance produces a 403 long after the last solve, falls outside
            // the window, and is re-solved normally.
            val solvedAt = lastSolvedAt[host]
            val fresh = solvedAt != null &&
                SystemClock.elapsedRealtime() - solvedAt < RECENT_SOLVE_WINDOW_MS
            if (fresh &&
                cookieManager.get(request.url).any { it.name == "cf_clearance" }
            ) {
                return
            }

            cookieManager.remove(request.url, COOKIE_NAMES, 0)
            val oldCookie = cookieManager.get(request.url)
                .firstOrNull { it.name == "cf_clearance" }
            resolveWithWebView(request, oldCookie)
            lastSolvedAt[host] = SystemClock.elapsedRealtime()
        }
    }

    override fun intercept(
        chain: Interceptor.Chain,
        request: Request,
        response: Response
    ): Response {
        try {
            response.close()
            solveOncePerHost(request)

            return chain.proceed(request)
        }
        // Because OkHttp's enqueue only handles IOExceptions, wrap the exception so that
        // we don't crash the entire app
        catch (e: CloudflareBypassException) {
            throw IOException("Failed to bypass Cloudflare")
        } catch (e: Exception) {
            throw IOException(e)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun resolveWithWebView(originalRequest: Request, oldCookie: Cookie?) {
        // We need to lock this thread until the WebView finds the challenge solution url, because
        // OkHttp doesn't support asynchronous interceptors.
        val latch = CountDownLatch(1)

        var webview: WebView? = null

        var challengeFound = false
        var cloudflareBypassed = false
        var isWebViewOutdated = false

        val origRequestUrl = originalRequest.url.toString()
        val headers = parseHeaders(originalRequest.headers)

        executor.execute {
            webview = createWebView(originalRequest)

            webview?.webViewClient = object : WebViewClientCompat() {
                override fun onPageFinished(view: WebView, url: String) {
                    fun isCloudFlareBypassed(): Boolean {
                        return cookieManager.get(origRequestUrl.toHttpUrl())
                            .firstOrNull { it.name == "cf_clearance" }
                            .let { it != null && it != oldCookie }
                    }

                    if (isCloudFlareBypassed()) {
                        cloudflareBypassed = true
                        latch.countDown()
                    }

                    if (url == origRequestUrl && !challengeFound) {
                        // The first request didn't return the challenge, abort.
                        latch.countDown()
                    }
                }

                override fun onReceivedErrorCompat(
                    view: WebView,
                    errorCode: Int,
                    description: String?,
                    failingUrl: String,
                    isMainFrame: Boolean,
                ) {
                    if (isMainFrame) {
                        if (errorCode in ERROR_CODES) {
                            // Found the Cloudflare challenge page.
                            challengeFound = true
                        } else {
                            // Unlock thread, the challenge wasn't found.
                            latch.countDown()
                        }
                    }
                }
            }

            webview?.loadUrl(origRequestUrl, headers)
        }

        latch.awaitFor30Seconds()

        executor.execute {
            if (!cloudflareBypassed) {
                isWebViewOutdated = webview?.isOutdated() == true
            }

            webview?.run {
                stopLoading()
                destroy()
            }
        }

        // Throw exception if we failed to bypass Cloudflare
        if (!cloudflareBypassed) {
            // Prompt user to update WebView if it seems too outdated
            if (isWebViewOutdated) {
                context.toast(
                    "Please update the webview app for better compatibility",
                    Toast.LENGTH_LONG
                )
            }

            throw CloudflareBypassException()
        }
    }
}

/**
 * How long after a successful solve a concurrent 403 is treated as stale rather
 * than as a reason to solve again. Comfortably longer than the request that
 * raced us, far shorter than a clearance cookie's lifetime.
 */
private const val RECENT_SOLVE_WINDOW_MS = 15_000L

private val ERROR_CODES = listOf(403, 503)
private val SERVER_CHECK = arrayOf("cloudflare-nginx", "cloudflare")
private val COOKIE_NAMES = listOf("cf_clearance")

class CloudflareBypassException : Exception()
