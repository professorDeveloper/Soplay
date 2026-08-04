package eu.kanade.tachiyomi

import com.soplay.sozo.BuildConfig

/**
 * Compatibility shim for Mihon's `eu.kanade.tachiyomi.AppInfo`.
 *
 * Modern Mihon/Keiyoushi extensions link against this object — MangaDex calls
 * `AppInfo.getVersionName()` to build its `User-Agent`, and it is referenced
 * indirectly by the shared `extensions-lib` code paths several others use. It
 * lives in the *host app*, not in the extension apk, so an app that hosts
 * extensions without providing it fails at class-resolution time:
 *
 *   NoClassDefFoundError: Failed resolution of: Leu/kanade/tachiyomi/AppInfo;
 *   Caused by: ClassNotFoundException: Didn't find class
 *              "eu.kanade.tachiyomi.AppInfo"
 *
 * The extension loads, then dies the moment it is used — which presented as a
 * source that installs fine and then shows an empty home.
 *
 * The values are Sozo's own. Extensions only ever use them for user-agent and
 * telemetry strings, so reporting ourselves honestly is both correct and the
 * least surprising thing to send upstream.
 */
object AppInfo {
    fun getVersionCode(): Int = BuildConfig.VERSION_CODE

    fun getVersionName(): String = BuildConfig.VERSION_NAME

    fun getPackageName(): String = BuildConfig.APPLICATION_ID

    fun getApplicationId(): String = BuildConfig.APPLICATION_ID

    fun getDebug(): Boolean = BuildConfig.DEBUG

    /**
     * Mihon uses this to gate preview-only behaviour. Sozo has no preview
     * channel, so this is always false — extensions branch on it for update
     * checks we do not participate in.
     */
    fun getIsPreview(): Boolean = false
}
