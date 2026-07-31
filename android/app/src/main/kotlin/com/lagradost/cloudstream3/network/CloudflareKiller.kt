package com.lagradost.cloudstream3.network

import android.content.Context
import android.util.Log
import eu.kanade.tachiyomi.network.AndroidCookieJar
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response
import java.io.IOException

/**
 * Clean-room stand-in for CloudStream's app-module `CloudflareKiller`, backed by
 * the Tachiyomi [CloudflareInterceptor] this app already ships.
 *
 * CloudStream plugins are compiled against the full app and pass this class to
 * `app.get(..., interceptor = CloudflareKiller())`. We only embed the CloudStream
 * `library` artifact, so the symbol has to exist here or those providers die with
 * `NoClassDefFoundError` before doing anything.
 *
 * It used to be a bare passthrough, which kept plugins loading but meant every
 * Cloudflare-gated CloudStream provider silently received the unsolved challenge
 * page. This now actually solves.
 *
 * ## Why it can't just delegate to [CloudflareInterceptor]
 *
 * That interceptor assumes it sits on a client whose [AndroidCookieJar] both
 * stores and replays cookies, so after solving it can plainly `chain.proceed`.
 * A plugin's client has no such jar — it constructs its own OkHttp instance and
 * only borrows this interceptor. So cookies must be attached to the request by
 * hand, both after a solve and on every subsequent request to a host we have
 * already solved. That is the whole reason [addCookies] exists.
 *
 * ## Limits, stated plainly
 *
 * This clears Cloudflare's **JS challenge** — the kind that resolves on its own
 * inside a WebView. It does not clear an interactive challenge (Turnstile
 * checkbox); no headless solver can, and the same is true of upstream
 * CloudStream and Mihon. For those, the user has to complete the challenge in
 * the visible solver (`CloudflareSolverPage`), and the cookies harvested there
 * land in the same system cookie store this class reads from.
 *
 * Even a valid `cf_clearance` is not always sufficient: Cloudflare also
 * fingerprints the TLS handshake, and OkHttp's differs from a browser's. A
 * source can therefore pass in the WebView and still be refused here. That is a
 * known, unsolved problem in every app of this kind — not something this class
 * can fix.
 */
class CloudflareKiller : Interceptor {

    /**
     * Host → cookie map, exposed because some plugins read it directly.
     * Populated for real now, unlike the passthrough version.
     */
    val savedCookies: MutableMap<String, Map<String, String>> = mutableMapOf()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()

        // Replay anything already solved for this host before even trying —
        // otherwise every request re-triggers a challenge the WebView already
        // cleared, and each one costs up to 30s.
        val response = chain.proceed(addCookies(request))
        if (!response.isCloudflareChallenge()) return response

        val interceptor = interceptorOrNull()
        if (interceptor == null) {
            Log.w(TAG, "Cloudflare challenge on ${request.url.host} but no context installed")
            return response
        }

        Log.i(TAG, "Cloudflare challenge on ${request.url.host}, solving")
        response.close()
        return try {
            interceptor.solveChallenge(request)
            harvest(request.url)
            chain.proceed(addCookies(request))
        } catch (t: Throwable) {
            // Surface the same message the manga/anime paths use, so the Dart
            // side's isCloudflareError() recognises it and can offer the
            // interactive solver instead of showing a raw stack trace.
            Log.e(TAG, "bypass failed for ${request.url.host}: ${t.message}")
            throw IOException("Failed to bypass Cloudflare")
        }
    }

    /** Reads whatever the system cookie store now holds for [url]. */
    private fun harvest(url: HttpUrl) {
        val raw = cookieJar.manager?.getCookie(url.toString())
        if (raw.isNullOrEmpty()) return
        savedCookies[url.host] = parseCookieMap(raw)
    }

    /**
     * Returns [request] with our cookies merged in.
     *
     * The request's own `Cookie` header wins on conflict: a plugin that set one
     * deliberately knows something we don't, and clobbering it would break
     * sources that carry their own session.
     */
    private fun addCookies(request: Request): Request {
        val stored = savedCookies[request.url.host]
            ?: cookieJar.manager?.getCookie(request.url.toString())
                ?.takeIf { it.isNotEmpty() }
                ?.let(::parseCookieMap)
            ?: return request
        if (stored.isEmpty()) return request

        val existing = request.header("Cookie")
            ?.let(::parseCookieMap)
            ?: emptyMap()
        val merged = stored + existing
        return request.newBuilder()
            .header("Cookie", merged.entries.joinToString("; ") { "${it.key}=${it.value}" })
            // The clearance cookie is bound to the UA that earned it. Sending a
            // different one gets it rejected, which looks exactly like "the
            // bypass didn't work".
            .header("User-Agent", request.header("User-Agent") ?: userAgent())
            .build()
    }

    /** Cookie headers for [url]; plugins call this to build their own requests. */
    fun getCookieHeaders(url: String): Headers {
        val host = url.toHttpUrlOrNull()?.host ?: return Headers.headersOf()
        val cookies = savedCookies[host] ?: return Headers.headersOf()
        if (cookies.isEmpty()) return Headers.headersOf()
        return Headers.headersOf(
            "Cookie",
            cookies.entries.joinToString("; ") { "${it.key}=${it.value}" },
        )
    }

    private fun interceptorOrNull(): CloudflareInterceptor? {
        val ctx = appContext ?: return null
        return cached ?: synchronized(this) {
            cached ?: CloudflareInterceptor(ctx, cookieJar, ::userAgent).also { cached = it }
        }
    }

    private var cached: CloudflareInterceptor? = null

    companion object {
        private const val TAG = "CloudflareKiller"

        /**
         * Application context, set once at startup.
         *
         * Static because plugins construct `CloudflareKiller()` with no
         * arguments — there is nowhere to inject it. Null means "not installed
         * yet", and every path degrades to the old passthrough rather than
         * crashing a plugin.
         */
        @Volatile
        private var appContext: Context? = null

        private val cookieJar: AndroidCookieJar by lazy { AndroidCookieJar() }

        fun install(context: Context) {
            appContext = context.applicationContext
        }

        /**
         * The device's real WebView user agent, shared with the OkHttp clients
         * on the manga/anime side. Matching matters: `cf_clearance` is issued
         * against the UA that solved the challenge.
         */
        private fun userAgent(): String = NetworkHelper.defaultUserAgentProvider()

        fun parseCookieMap(cookie: String): Map<String, String> =
            cookie.split(";").mapNotNull {
                val k = it.substringBefore("=").trim()
                val v = it.substringAfter("=", "").trim()
                if (k.isEmpty()) null else k to v
            }.toMap()

        private val ERROR_CODES = listOf(403, 503)
        private val SERVER_CHECK = arrayOf("cloudflare-nginx", "cloudflare")

        /**
         * Same test the Tachiyomi interceptor uses. Status alone is not enough —
         * plenty of sources return a legitimate 403 — so the `Server` header has
         * to agree.
         */
        private fun Response.isCloudflareChallenge(): Boolean =
            code in ERROR_CODES && header("Server") in SERVER_CHECK
    }
}
