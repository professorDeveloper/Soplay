package com.soplay.sozo.extensions

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Turns an inbound "open this file with Sozo" intent into something the Flutter
 * side can act on.
 *
 * Extension repos are distributed as a single index file — `index.pb` (Mihon /
 * Keiyoushi), `index.min.json` (Aniyomi / older forks), `repo.json`
 * (CloudStream) or `index.json` (Mangayomi). Tapping one in a browser, a file
 * manager, or Telegram now offers Sozo in the chooser; this resolves whatever
 * the sender handed us (`content://`, `file://` or a plain `https://` link) into
 * `{ kind, name, url|path }` and hands it over so the app can show an install
 * dialog.
 *
 * `content://` URIs are copied into our cache directory: the grant that came
 * with the intent is scoped to this task and is gone by the time the user
 * confirms the dialog, so holding on to the URI would fail at exactly the wrong
 * moment.
 */
object RepoFileIntent {

    private const val TAG = "RepoFileIntent"

    /** How the app should install what was opened. Mirrors the repo-manager split. */
    const val KIND_MANGA = "manga"
    const val KIND_ANIYOMI = "aniyomi"
    const val KIND_CLOUDSTREAM = "cloudstream"
    const val KIND_MANGAYOMI = "mangayomi"
    const val KIND_UNKNOWN = "unknown"

    /**
     * Extracts a pending repo file from [intent], or null when the intent isn't
     * one (a normal launch, a deeplink the DeeplinkService owns, …).
     *
     * Returns a JSON string: `{"kind","name","path"?,"url"?,"size"?}`.
     */
    fun extract(context: Context, intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW && intent.action != Intent.ACTION_SEND) return null

        val uri: Uri = when (intent.action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    ?: intent.getStringExtra(Intent.EXTRA_TEXT)?.let(Uri::parse)
                    ?: return null
            }
            else -> intent.data ?: return null
        }

        val displayName = displayName(context, uri)
        // http(s) links are handled without a copy — the repo managers fetch urls
        // natively, and downloading here would just duplicate that.
        if (uri.scheme == "http" || uri.scheme == "https") {
            if (!looksLikeIndex(displayName, uri.toString())) return null
            return JSONObject().apply {
                put("kind", kindFor(displayName, uri.toString()))
                put("name", displayName)
                put("url", uri.toString())
            }.toString()
        }

        if (uri.scheme != "content" && uri.scheme != "file") return null
        if (!looksLikeIndex(displayName, uri.toString())) return null

        val copied = copyToCache(context, uri, displayName) ?: return null
        return JSONObject().apply {
            put("kind", kindFor(displayName, uri.toString()))
            put("name", displayName)
            put("path", copied.absolutePath)
            put("size", copied.length())
        }.toString()
    }

    /**
     * Whether this file is plausibly an extension index.
     *
     * Deliberately name-based and permissive: the manifest already narrows what
     * reaches us, and a wrong guess here costs the user one dismissed dialog,
     * while a miss costs them the feature. The real validation is the parse.
     */
    private fun looksLikeIndex(name: String, uri: String): Boolean {
        val n = (name.ifEmpty { uri.substringAfterLast('/') }).lowercase()
        return n.endsWith(".pb") ||
            n.endsWith("index.json") ||
            n.endsWith("index.min.json") ||
            n.endsWith("repo.json") ||
            n.contains("anime_index") ||
            n.contains("novel_index")
    }

    /**
     * Best-effort routing to a repo manager. `index.pb` and `index.min.json` are
     * shared by the manga and anime ecosystems and the file itself doesn't say
     * which, so those resolve to [KIND_UNKNOWN] and the app asks the user.
     */
    private fun kindFor(name: String, uri: String): String {
        val hay = (name + " " + uri).lowercase()
        return when {
            hay.contains("repo.json") -> KIND_CLOUDSTREAM
            hay.contains("anime_index") || hay.contains("novel_index") -> KIND_MANGAYOMI
            hay.contains("anime-repo") || hay.contains("aniyomi") -> KIND_ANIYOMI
            hay.contains("manga-repo") || hay.contains("mangayomi") -> KIND_MANGAYOMI
            hay.contains("keiyoushi") || hay.contains("mihon") || hay.contains("tachiyomi") -> KIND_MANGA
            else -> KIND_UNKNOWN
        }
    }

    private fun displayName(context: Context, uri: Uri): String {
        if (uri.scheme == "content") {
            try {
                context.contentResolver.query(uri, null, null, null, null)?.use { c ->
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && c.moveToFirst()) {
                        val v = c.getString(idx)
                        if (!v.isNullOrEmpty()) return v
                    }
                }
            } catch (t: Throwable) {
                Log.e(TAG, "displayName query failed: ${t.message}")
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/').orEmpty()
    }

    private fun copyToCache(context: Context, uri: Uri, name: String): File? {
        return try {
            val dir = File(context.cacheDir, "repo_import").apply { mkdirs() }
            // Overwrite rather than accumulate: these are one-shot imports and the
            // cache dir is not a place to leak a copy per tap.
            val safe = name.ifEmpty { "index" }.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val out = File(dir, safe)
            val stream = context.contentResolver.openInputStream(uri) ?: return null
            stream.use { input -> out.outputStream().use { input.copyTo(it) } }
            if (out.length() <= 0) {
                out.delete(); null
            } else {
                Log.i(TAG, "imported ${out.name} (${out.length()} bytes)")
                out
            }
        } catch (t: Throwable) {
            Log.e(TAG, "copyToCache failed: ${t.message}")
            null
        }
    }
}
