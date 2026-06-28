package com.soplay.sozo.manga

import android.content.Context
import android.util.Log
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.SChapterImpl
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.SMangaImpl
import eu.kanade.tachiyomi.source.online.HttpSource
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Bridges Mihon/Tachiyomi manga [CatalogueSource]s to the soplay JSON contracts.
 * Mirror of `AniyomiHost` but: providers are namespaced `mn:` (group "manga"),
 * `load` returns chapters as the `episodes` array (a chapter is structurally an
 * episode), and instead of `loadLinks`→videoSources it exposes `pageList`→pages.
 */
class MangaHost(private val context: Context) {

    companion object {
        private const val TAG = "MangaHost"
        private const val UA =
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
    }

    private data class SourceMeta(
        val id: String,
        val name: String,
        val lang: String,
        val baseUrl: String,
        val pkg: String,
        val className: String,
        val apkUrl: String,
        val iconUrl: String,
        val nsfw: Boolean,
        val repoName: String,
    )

    private val sources = LinkedHashMap<String, SourceMeta>()

    // Home pages are expensive (network scrape + HTML parse). Cache the built
    // JSON briefly so navigating away and back is instant instead of re-scraping.
    private data class CacheEntry(val ts: Long, val json: String)
    private val pageCache = HashMap<String, CacheEntry>()
    private val cacheTtlMs = 5 * 60 * 1000L

    fun registerMeta(entry: JSONObject, repoName: String) {
        val id = entry.optString("id")
        if (id.isEmpty()) return
        sources[id] = SourceMeta(
            id = id,
            name = entry.optString("name"),
            lang = entry.optString("lang"),
            baseUrl = entry.optString("baseUrl"),
            pkg = entry.optString("pkg"),
            className = entry.optString("className"),
            apkUrl = entry.optString("apkUrl"),
            iconUrl = entry.optString("iconUrl"),
            nsfw = entry.optBoolean("nsfw", false),
            repoName = repoName,
        )
    }

    fun removeSources(ids: List<String>) {
        ids.forEach { sources.remove(it) }
    }

    private fun langRank(lang: String): Int = when (lang.trim().lowercase()) {
        "en" -> 0
        "all" -> 1
        else -> 2
    }

    fun providersJson(): String {
        val picked = LinkedHashMap<String, SourceMeta>()
        for (s in sources.values) {
            val key = s.name.trim().lowercase()
            if (key.isEmpty()) continue
            val cur = picked[key]
            if (cur == null || langRank(s.lang) < langRank(cur.lang)) picked[key] = s
        }
        val arr = JSONArray()
        for (s in picked.values) {
            arr.put(JSONObject().apply {
                put("id", "mn:${s.id}")
                put("name", s.name)
                put("lang", s.lang)
                put("baseUrl", s.baseUrl)
                put("icon", s.iconUrl)
                put("nsfw", s.nsfw)
                put("repo", s.repoName)
                put("mode", "client")
                put("group", "manga")
            })
        }
        return arr.toString()
    }

    // --- runtime: load source + convert to soplay JSON ---

    private fun ensureApk(meta: SourceMeta): File? {
        if (meta.apkUrl.isEmpty()) return null
        val dir = File(context.filesDir, "manga").apply { mkdirs() }
        val file = File(dir, (meta.pkg.ifEmpty { meta.id }).replace('/', '_') + ".apk")
        if (file.exists() && file.length() > 0) return file
        return try {
            val conn = (URL(meta.apkUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"; instanceFollowRedirects = true
                connectTimeout = 20000; readTimeout = 60000
                setRequestProperty("User-Agent", UA)
            }
            if (conn.responseCode !in 200..299) {
                Log.e(TAG, "apk ${meta.apkUrl} -> ${conn.responseCode}"); return null
            }
            conn.inputStream.use { input -> FileOutputStream(file).use { input.copyTo(it) } }
            file
        } catch (t: Throwable) {
            Log.e(TAG, "apk download failed: ${t.message}"); null
        }
    }

    private fun sourceFor(id: String): CatalogueSource? {
        val meta = sources[id] ?: return null
        val apk = ensureApk(meta) ?: return null
        return MangaRuntime.source(context, apk.absolutePath, meta.pkg, meta.id)
    }

    private fun cardJson(m: SManga, id: String) = JSONObject().apply {
        put("provider", "mn:$id")
        put("externalId", m.url)
        put("title", m.title)
        put("slug", m.url)
        put("contentUrl", m.url)
        put("thumbnail", m.thumbnail_url)
        put("type", "Manga")
    }

    private fun newManga(url: String) = SMangaImpl().apply { this.url = url; title = "" }

    fun getMainPageJson(id: String, page: Int): String {
        val cacheKey = "main:$id:$page"
        pageCache[cacheKey]?.let {
            if (System.currentTimeMillis() - it.ts < cacheTtlMs) return it.json
        }

        val src = sourceFor(id)
        val sections = JSONArray()
        val banner = JSONArray()
        var queryError: String? = null
        if (src != null) {
            // Fetch popular + latest CONCURRENTLY (was sequential, which doubled the
            // wall-clock of every home load).
            val popular: Result<eu.kanade.tachiyomi.source.model.MangasPage>
            val latest: Result<eu.kanade.tachiyomi.source.model.MangasPage?>
            runBlocking {
                // runCatching INSIDE each job so one failing call can't cancel
                // the sibling via the shared parent scope.
                val popJob = async(Dispatchers.IO) {
                    runCatching { src.getPopularManga(page) }
                }
                val latJob = async(Dispatchers.IO) {
                    runCatching {
                        if (src.supportsLatest) src.getLatestUpdates(page) else null
                    }
                }
                popular = popJob.await()
                latest = latJob.await()
            }

            popular.getOrNull()?.let { pop ->
                val items = JSONArray()
                for (m in pop.mangas.take(30)) items.put(cardJson(m, id))
                if (items.length() > 0) {
                    var i = 0
                    while (i < items.length() && i < 12) { banner.put(items.get(i)); i++ }
                    sections.put(JSONObject().apply {
                        put("key", "popular"); put("label", "Popular")
                        put("viewAll", JSONObject().apply { put("type", "mn"); put("slug", "popular") })
                        put("items", items)
                    })
                }
            }
            popular.exceptionOrNull()?.let { t ->
                queryError = "getPopular: ${t.javaClass.simpleName}: ${t.message}"
                Log.e(TAG, "getPopular $id", t)
            }

            latest.getOrNull()?.let { lat ->
                val items = JSONArray()
                for (m in lat.mangas.take(30)) items.put(cardJson(m, id))
                if (items.length() > 0) sections.put(JSONObject().apply {
                    put("key", "latest"); put("label", "Latest")
                    put("viewAll", JSONObject().apply { put("type", "mn"); put("slug", "latest") })
                    put("items", items)
                })
            }
            latest.exceptionOrNull()?.let { t ->
                if (queryError == null) queryError = "getLatest: ${t.javaClass.simpleName}: ${t.message}"
                Log.e(TAG, "getLatest $id", t)
            }
        }

        val json = JSONObject().apply {
            put("provider", "mn:$id"); put("banner", banner); put("sections", sections)
            // Surface the real failure (otherwise the home is silently empty).
            if (src == null) {
                put("error", MangaRuntime.lastError ?: "source unavailable: mn:$id")
            } else if (sections.length() == 0 && queryError != null) {
                put("error", queryError)
            }
        }.toString()
        // Cache only successful pages so an error/empty isn't pinned for 5 min.
        if (sections.length() > 0) pageCache[cacheKey] = CacheEntry(System.currentTimeMillis(), json)
        return json
    }

    fun getSectionJson(id: String, data: String, page: Int): String {
        val src = sourceFor(id)
        val items = JSONArray()
        var hasNext = false
        if (src != null) try {
            val pg = runBlocking {
                if (data == "latest" && src.supportsLatest) src.getLatestUpdates(page)
                else src.getPopularManga(page)
            }
            for (m in pg.mangas) items.put(cardJson(m, id))
            hasNext = pg.hasNextPage
        } catch (t: Throwable) { Log.e(TAG, "getSection $id: ${t.message}") }
        return JSONObject().apply {
            put("provider", "mn:$id"); put("items", items); put("page", page)
            put("totalPages", if (hasNext) page + 1 else page)
        }.toString()
    }

    fun searchJson(id: String, query: String, page: Int = 1): String {
        val src = sourceFor(id)
        val items = JSONArray()
        var hasNext = false
        if (src != null) try {
            val pg = runBlocking { src.getSearchManga(page, query, FilterList()) }
            for (m in pg.mangas) items.put(cardJson(m, id))
            hasNext = pg.hasNextPage
        } catch (t: Throwable) { Log.e(TAG, "search $id: ${t.message}") }
        return JSONObject().apply {
            put("provider", "mn:$id"); put("items", items)
            put("query", query); put("page", page)
            put("totalPages", if (hasNext) page + 1 else page)
        }.toString()
    }

    fun getGenresJson(id: String): String = "[]"

    /**
     * Returns `{"baseUrl","userAgent"}` for the interactive Cloudflare solver.
     * The userAgent is the EXACT one the native OkHttp client sends for this
     * source (the source's own header, falling back to [NetworkHelper]'s default)
     * so the harvested `cf_clearance` cookie — which is UA-bound — is accepted.
     * Returns `{}` when the source can't be resolved or has no base url.
     */
    fun cloudflareInfo(id: String): String {
        val meta = sources[id]
        val src = sourceFor(id) as? HttpSource
        val baseUrl = (src?.baseUrl ?: meta?.baseUrl).orEmpty()
        if (baseUrl.isEmpty()) return "{}"
        val ua = src?.headers?.get("User-Agent")
            ?: NetworkHelper.defaultUserAgentProvider()
        return JSONObject().apply {
            put("baseUrl", baseUrl)
            put("userAgent", ua)
        }.toString()
    }

    private fun statusLabel(status: Int): String? = when (status) {
        1 -> "Ongoing"
        2 -> "Completed"
        3 -> "Licensed"
        4 -> "Publishing finished"
        5 -> "Cancelled"
        6 -> "On hiatus"
        else -> null
    }

    fun loadJson(id: String, url: String): String {
        val cacheKey = "load:$id:$url"
        pageCache[cacheKey]?.let {
            if (System.currentTimeMillis() - it.ts < cacheTtlMs) return it.json
        }
        val src = sourceFor(id) ?: return "{}"
        val manga = newManga(url)
        // details + chapter list are independent → fetch concurrently (was two
        // sequential network round-trips on every detail open).
        val (details, chaps) = runBlocking {
            // Catch INSIDE each async body. With runCatching only around await(),
            // a throw inside one job (e.g. a source with a malformed details/
            // chapters JSON) propagates to this scope and CANCELS the sibling
            // ("Parent job is Cancelling") — so one bad source killed both. Now
            // each job swallows its own failure and the two are independent.
            val detJob = async(Dispatchers.IO) {
                runCatching { src.getMangaDetails(manga) }
                    .onFailure { Log.e(TAG, "details $id", it) }
                    .getOrDefault(manga)
            }
            val chapJob = async(Dispatchers.IO) {
                runCatching { src.getChapterList(manga) }
                    .onFailure { Log.e(TAG, "chapters $id", it) }
                    .getOrDefault(emptyList<eu.kanade.tachiyomi.source.model.SChapter>())
            }
            Pair(detJob.await(), chapJob.await())
        }

        // Reading order = oldest→newest so episodeIndex 0 is chapter 1. Sources usually
        // return newest-first; sort by chapter_number when parsed, else reverse source order.
        val ordered =
            if (chaps.any { it.chapter_number > 0 }) chaps.sortedBy { it.chapter_number }
            else chaps.reversed()
        val episodes = JSONArray()
        ordered.forEachIndexed { i, c ->
            episodes.put(JSONObject().apply {
                put("episode", i + 1)
                put("label", c.name.ifEmpty { "Chapter ${i + 1}" })
                put("mediaRef", c.url)
            })
        }

        val title = try { details.title } catch (_: Throwable) { "" }
        val author = try { details.author } catch (_: Throwable) { null }
        val status = statusLabel(try { details.status } catch (_: Throwable) { 0 })
        val desc = buildString {
            status?.let { append("• ").append(it) }
            val d = try { details.description } catch (_: Throwable) { null }
            if (!d.isNullOrBlank()) {
                if (isNotEmpty()) append("\n\n")
                append(d)
            }
        }
        // Manga has no "recommendations" API, so derive a "similar" row from a title search.
        val related = JSONArray()
        try {
            val q = title.replace(Regex("\\(.*?\\)"), "").trim()
            if (q.length >= 2) {
                val results = runBlocking { src.getSearchManga(1, q, FilterList()) }
                for (m in results.mangas) {
                    if (m.url == url) continue
                    related.put(cardJson(m, id))
                    if (related.length() >= 20) break
                }
            }
        } catch (t: Throwable) { Log.e(TAG, "related $id: ${t.message}") }

        val json = JSONObject().apply {
            put("provider", "mn:$id")
            put("contentId", url); put("contentUrl", url)
            put("title", title)
            put("description", desc)
            put("thumbnail", details.thumbnail_url)
            put("banner", details.thumbnail_url)
            put("year", JSONObject.NULL)
            if (!author.isNullOrBlank()) put("director", author)
            put("genres", JSONArray(details.getGenres() ?: emptyList<String>()))
            put("type", "Manga")
            put("isSerial", true)
            put("cast", JSONArray())
            put("related", related)
            put("episodes", episodes)
        }.toString()
        if (title.isNotEmpty()) {
            pageCache[cacheKey] = CacheEntry(System.currentTimeMillis(), json)
        }
        return json
    }

    /**
     * Resolves a chapter's page list to image URLs. [data] is the chapter's `mediaRef`
     * (the source-relative chapter url). Returns `{provider, headers, pages:[{index,imageUrl}]}`;
     * the shared [headers] (referer/UA) must be applied to every image request by the reader.
     */
    fun pageListJson(id: String, data: String): String {
        val src = sourceFor(id) ?: return "{}"
        val http = src as? HttpSource
        val chapter = SChapterImpl().apply { url = data; name = "" }
        val pages = try { runBlocking { src.getPageList(chapter) } }
        catch (t: Throwable) { Log.e(TAG, "pages $id: ${t.message}"); emptyList() }

        val pagesArr = JSONArray()
        for (p in pages) {
            var img = p.imageUrl
            // Some sources defer the real image url to getImageUrl(page).
            if ((img.isNullOrEmpty()) && p.url.isNotEmpty() && http != null) {
                img = try { runBlocking { http.getImageUrl(p) } }
                catch (t: Throwable) { Log.e(TAG, "imageUrl $id: ${t.message}"); null }
            }
            if (img.isNullOrEmpty()) continue
            pagesArr.put(JSONObject().apply {
                put("index", p.index)
                put("imageUrl", img)
            })
        }
        val headers = JSONObject()
        http?.headers?.forEach { (k, value) -> headers.put(k, value) }
        return JSONObject().apply {
            put("provider", "mn:$id")
            put("headers", headers)
            put("pages", pagesArr)
        }.toString()
    }

    // --- per-source settings (ConfigurableSource) ---

    /** Returns the source's preferences as a JSON array, or `[]` if none. */
    fun getPrefsJson(id: String): String {
        val src = sourceFor(id) ?: return "[]"
        if (src !is ConfigurableSource) return "[]"
        return try {
            MangaPreferences.extract(context, id, src)
        } catch (t: Throwable) {
            Log.e(TAG, "prefs $id: ${t.message}"); "[]"
        }
    }

    /** Persists a single preference value to the source's SharedPreferences. */
    fun setPrefJson(id: String, key: String, value: Any?, type: String): String {
        return try {
            MangaPreferences.write(context, id, key, value, type)
            "{\"ok\":true}"
        } catch (t: Throwable) {
            Log.e(TAG, "setPref $id: ${t.message}"); "{\"ok\":false}"
        }
    }
}
