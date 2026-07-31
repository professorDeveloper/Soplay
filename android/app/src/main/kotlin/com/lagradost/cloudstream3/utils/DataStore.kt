package com.lagradost.cloudstream3.utils

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.preference.PreferenceManager

/**
 * Clean-room stand-in for CloudStream's app-module `DataStore`.
 *
 * Plugins use it (usually via `CloudStreamApp.getKey`/`setKey`) to persist small
 * bits of state — a selected server, a saved token, a last-used quality. The
 * class lives in the app module, which we do not embed, so any plugin touching
 * it died with `NoClassDefFoundError`.
 *
 * ## Storage shape
 *
 * Upstream serialises every value to JSON with Jackson and stores the string.
 * We store primitives natively and anything else as its `toString()`, then only
 * hand back values whose requested type we can actually produce.
 *
 * The consequence, stated plainly: a plugin that round-trips a **data class**
 * through `setKey`/`getKey` will get `null` back rather than its object. That is
 * a real behavioural gap versus upstream — but it is a *quiet* one, and the code
 * paths that use it already treat null as "nothing saved yet". Crashing on a
 * missing class, which is what happens without this file, is strictly worse.
 * If a plugin turns out to need object round-tripping, the fix is to serialise
 * through the library's own `AppUtils.parseJson` here.
 */
object DataStore {

    private const val TAG = "DataStore"

    fun Context.getSharedPrefs(): SharedPreferences =
        PreferenceManager.getDefaultSharedPreferences(this)

    fun Context.getDefaultSharedPrefs(): SharedPreferences =
        PreferenceManager.getDefaultSharedPreferences(this)

    /** Upstream's key layout, kept identical so stored keys stay compatible. */
    fun getFolderName(folder: String, path: String): String = "${folder}/${path}"

    fun getKeys(context: Context, folder: String): List<String> =
        context.getSharedPrefs().all.keys.filter { it.startsWith(folder) }

    fun containsKey(context: Context, path: String): Boolean =
        context.getSharedPrefs().contains(path)

    fun removeKey(context: Context, path: String) {
        try {
            context.getSharedPrefs().edit().remove(path).apply()
        } catch (t: Throwable) {
            Log.e(TAG, "removeKey($path) failed: ${t.message}")
        }
    }

    fun removeKeys(context: Context, folder: String): Int {
        val keys = getKeys(context, folder)
        keys.forEach { removeKey(context, it) }
        return keys.size
    }

    fun <T> setKeyAny(context: Context, path: String, value: T) {
        try {
            val editor = context.getSharedPrefs().edit()
            when (value) {
                null -> editor.remove(path)
                is String -> editor.putString(path, value)
                is Int -> editor.putInt(path, value)
                is Long -> editor.putLong(path, value)
                is Float -> editor.putFloat(path, value)
                is Double -> editor.putString(path, value.toString())
                is Boolean -> editor.putBoolean(path, value)
                else -> editor.putString(path, value.toString())
            }
            editor.apply()
        } catch (t: Throwable) {
            Log.e(TAG, "setKey($path) failed: ${t.message}")
        }
    }

    fun <T : Any> setKeyClass(context: Context, path: String, value: T) =
        setKeyAny(context, path, value)

    /**
     * Returns the stored value for [path] coerced to [valueType], or null when
     * nothing is stored or the stored value cannot be represented as that type.
     */
    @Suppress("UNCHECKED_CAST")
    fun <T : Any> getKeyClass(context: Context, path: String, valueType: Class<T>): T? {
        return try {
            val prefs = context.getSharedPrefs()
            if (!prefs.contains(path)) return null
            val raw = prefs.all[path] ?: return null
            when {
                valueType.isInstance(raw) -> raw as T
                valueType == String::class.java -> raw.toString() as T
                valueType == java.lang.Integer::class.java || valueType == Int::class.java ->
                    raw.toString().toIntOrNull() as? T
                valueType == java.lang.Long::class.java || valueType == Long::class.java ->
                    raw.toString().toLongOrNull() as? T
                valueType == java.lang.Float::class.java || valueType == Float::class.java ->
                    raw.toString().toFloatOrNull() as? T
                valueType == java.lang.Double::class.java || valueType == Double::class.java ->
                    raw.toString().toDoubleOrNull() as? T
                valueType == java.lang.Boolean::class.java || valueType == Boolean::class.java ->
                    raw.toString().toBooleanStrictOrNull() as? T
                else -> null
            }
        } catch (t: Throwable) {
            Log.e(TAG, "getKey($path) failed: ${t.message}")
            null
        }
    }
}
