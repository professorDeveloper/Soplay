package com.soplay.sozo.manga

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import com.soplay.sozo.aniyomi.AniyomiRuntime
import dalvik.system.DexClassLoader
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import java.io.File

/**
 * Loads Mihon/Tachiyomi MANGA extension APKs at runtime and exposes their
 * [CatalogueSource]s. Structurally identical to [AniyomiRuntime] but keyed on the
 * manga metadata class (`tachiyomi.extension.class`) and the manga `source` tree.
 *
 * The Injekt singletons (NetworkHelper / JavaScriptEngine / Json / Application) are
 * shared with the anime runtime — manga and anime extensions link against the same
 * `eu.kanade.tachiyomi.network` layer — so we delegate bootstrap to [AniyomiRuntime].
 */
object MangaRuntime {

    private const val TAG = "MangaRuntime"
    private const val METADATA_SOURCE_CLASS = "tachiyomi.extension.class"

    private val sourceCache = HashMap<String, CatalogueSource>()
    private val loadedApks = HashSet<String>()

    /** Last load/instantiate failure reason, surfaced to the UI for diagnosis. */
    @Volatile
    var lastError: String? = null
        private set

    /**
     * Returns the [CatalogueSource] whose id matches [sourceId], loading the APK once
     * and caching every source it declares. Returns null when the apk can't be
     * parsed/loaded or has no matching source.
     */
    fun source(context: Context, apkPath: String, pkg: String, sourceId: String): CatalogueSource? {
        sourceCache[sourceId]?.let { return it }
        // Shared Injekt singletons (NetworkHelper, JavaScriptEngine, Json, Application).
        AniyomiRuntime.bootstrap(context)
        if (loadedApks.contains(apkPath)) return sourceCache[sourceId]
        synchronized(this) {
            if (!loadedApks.contains(apkPath)) {
                // Mark loaded BEFORE attempting: a failure (bad apk, link error) must not
                // retry on every home reload.
                loadedApks.add(apkPath)
                try {
                    loadApk(context, apkPath, pkg)
                } catch (t: Throwable) {
                    lastError = "loadApk: ${t.javaClass.simpleName}: ${t.message}"
                    // Pass the throwable so the full stack + `Caused by:` chain is
                    // logged (the exact missing/changed symbol) — not just message.
                    Log.e(TAG, "loadApk failed for $apkPath", t)
                }
            }
        }
        return sourceCache[sourceId]
    }

    private fun loadApk(context: Context, apkPath: String, pkg: String) {
        val pm = context.packageManager
        val info = pm.getPackageArchiveInfo(apkPath, PackageManager.GET_META_DATA) ?: run {
            Log.e(TAG, "getPackageArchiveInfo null: $apkPath"); return
        }
        val appInfo = info.applicationInfo ?: return
        val classList = appInfo.metaData?.getString(METADATA_SOURCE_CLASS) ?: run {
            Log.e(TAG, "no $METADATA_SOURCE_CLASS metadata"); return
        }
        // Android (API 26+) refuses to DexClassLoad a writable file (W^X). The apk lives
        // in our writable filesDir, so mark it read-only before loading.
        try { File(apkPath).setReadOnly() } catch (_: Throwable) {}
        val optimizedDir = File(context.codeCacheDir, "manga_dex").apply { mkdirs() }
        val loader = DexClassLoader(apkPath, optimizedDir.absolutePath, null, javaClass.classLoader)

        for (raw in classList.split(";").map { it.trim() }.filter { it.isNotEmpty() }) {
            val className = if (raw.startsWith(".")) pkg + raw else raw
            val instance = try {
                val clazz = loader.loadClass(className)
                clazz.getDeclaredConstructor().newInstance()
            } catch (t: Throwable) {
                lastError = "instantiate $className: ${t.javaClass.simpleName}: ${t.message}"
                Log.e(TAG, "instantiate $className failed", t)
                continue
            }
            val sources = when (instance) {
                is SourceFactory -> instance.createSources()
                is Source -> listOf(instance)
                else -> emptyList()
            }
            sources.filterIsInstance<CatalogueSource>().forEach {
                sourceCache[it.id.toString()] = it
            }
        }
    }
}
