package com.soplay.sozo.aniyomi

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import dalvik.system.DexClassLoader
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import java.io.File

object AniyomiRuntime {

    private const val TAG = "AniyomiRuntime"
    private const val METADATA_SOURCE_CLASS = "tachiyomi.animeextension.class"

    @Volatile private var bootstrapped = false
    private val sourceCache = HashMap<String, AnimeCatalogueSource>()
    private val loadedApks = HashSet<String>()

    fun bootstrap(context: Context) {
        if (bootstrapped) return
        synchronized(this) {
            if (bootstrapped) return
            val app = context.applicationContext
            Injekt.addSingletonFactory { NetworkHelper(app) }
            Injekt.addSingletonFactory {
                Json {
                    ignoreUnknownKeys = true
                    coerceInputValues = true
                }
            }
            bootstrapped = true
        }
    }

    /**
     * Returns the [AnimeCatalogueSource] whose id matches [sourceId], loading the
     * APK once and caching every source it declares. Returns null when the apk
     * can't be parsed/loaded or has no matching source.
     */
    fun source(context: Context, apkPath: String, pkg: String, sourceId: String): AnimeCatalogueSource? {
        sourceCache[sourceId]?.let { return it }
        bootstrap(context)
        if (loadedApks.contains(apkPath)) return sourceCache[sourceId]
        synchronized(this) {
            if (!loadedApks.contains(apkPath)) {
                loadApk(context, apkPath, pkg)
                loadedApks.add(apkPath)
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
        val optimizedDir = File(context.codeCacheDir, "aniyomi_dex").apply { mkdirs() }
        val loader = DexClassLoader(apkPath, optimizedDir.absolutePath, null, javaClass.classLoader)

        for (raw in classList.split(";").map { it.trim() }.filter { it.isNotEmpty() }) {
            val className = if (raw.startsWith(".")) pkg + raw else raw
            val instance = try {
                val clazz = loader.loadClass(className)
                clazz.getDeclaredConstructor().newInstance()
            } catch (t: Throwable) {
                Log.e(TAG, "instantiate $className failed: ${t.message}"); continue
            }
            val sources = when (instance) {
                is AnimeSourceFactory -> instance.createSources()
                is AnimeSource -> listOf(instance)
                else -> emptyList()
            }
            sources.filterIsInstance<AnimeCatalogueSource>().forEach {
                sourceCache[it.id.toString()] = it
            }
        }
    }
}
