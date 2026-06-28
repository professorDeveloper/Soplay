-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,Exceptions,InnerClasses,EnclosingMethod

# Flutter engine + plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# App's own native code (MainActivity, DownloadForegroundService)
-keep class com.soplay.sozo.** { *; }

# Firebase: core / messaging / crashlytics / analytics
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.android.datatransport.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# flutter_local_notifications — uses Gson reflection for scheduled payloads
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# Gson (pulled in by flutter_local_notifications)
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn sun.misc.**

# flutter_inappwebview — JavaScript bridges
-keep class com.pichillilorenzo.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# video_player — ExoPlayer / Media3
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# flutter_secure_storage / local_auth (androidx.security + biometric)
-keep class androidx.security.crypto.** { *; }
-keep class androidx.biometric.** { *; }

# Parcelable / enums / Serializable — reflection-sensitive
-keep class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep generated R inner-class fields (used by shrinkResources)
-keepclassmembers class **.R$* {
    public static <fields>;
}

# Native (JNI) methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# CloudStream runtime (com.github.recloudstream.cloudstream:library) + our locally
# re-declared Plugin base. Loaded .cs3 plugins resolve these by EXACT class/method
# name via PathClassLoader, so they must never be stripped or obfuscated.
-keep class com.lagradost.** { *; }
-keep interface com.lagradost.** { *; }
-dontwarn com.lagradost.**
# Rhino JS engine + parsers transitively pulled by the library (used by extractors).
-keep class org.mozilla.javascript.** { *; }
-dontwarn org.mozilla.javascript.**

# Runtime-loaded .cs3 plugins reference the CloudStream library's transitive deps
# BY ORIGINAL NAME (they're compiled against the full app). R8 can't see those
# reflective uses, so without explicit keeps it shrinks/obfuscates them and every
# plugin fails to load in release (works in debug where R8 is off). Keep the whole
# dependency surface the plugins touch.
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class org.jsoup.** { *; }
-dontwarn org.jsoup.**
-keep class org.schabi.newpipe.** { *; }
-dontwarn org.schabi.newpipe.**
# CloudStream parses JSON with Jackson (+ jackson-module-kotlin via reflection).
-keep class com.fasterxml.jackson.** { *; }
-keep class com.fasterxml.** { *; }
-dontwarn com.fasterxml.jackson.**
# nicehttp (com.lagradost.* — already kept above) + NanoHTTPD if present.
-dontwarn fi.iki.elonen.**
-keep class fi.iki.elonen.** { *; }
# Plugins use Kotlin stdlib/coroutines/reflection that our own app may not, so R8
# would otherwise strip them. Keep + preserve Kotlin metadata for reflection.
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class kotlin.reflect.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**

# ---------------------------------------------------------------------------
# Aniyomi (anime) + Manga extension runtime. Extension .apk's are DexClassLoad'ed
# with the app as parent classloader (see AniyomiRuntime.loadApk /
# MangaRuntime.loadApk) and resolve the host's vendored APIs + transitive libs BY
# ORIGINAL NAME. R8 can't see those reflective uses, so without these keeps it
# shrinks/obfuscates the classes and every extension fails to load in release
# (works in debug where R8 is off) — no Aniyomi/Manga providers ever appear.
# Same failure mode as CloudStream above; keep the whole surface extensions touch.
#
# This one wildcard covers BOTH the anime API (eu.kanade.tachiyomi.animesource.**)
# and the manga API (eu.kanade.tachiyomi.source.**); their hosts/runtimes are kept
# by the `com.soplay.sozo.**` rule above (covers com.soplay.sozo.aniyomi.** and
# com.soplay.sozo.manga.**). Do NOT narrow this to `.animesource` — that would
# strip the manga source-api and break manga extension loading in release.
-keep class eu.kanade.tachiyomi.** { *; }
-keep interface eu.kanade.tachiyomi.** { *; }
-dontwarn eu.kanade.tachiyomi.**
# Injekt DI: extensions resolve NetworkHelper/JavaScriptEngine via Injekt.get().
-keep class uy.kohesive.injekt.** { *; }
-dontwarn uy.kohesive.injekt.**
# RxJava 1 (io.reactivex:rxjava:1.3.8 → package `rx`): the AnimeSource API exposes
# Observable-based methods that many extensions still override.
-keep class rx.** { *; }
-dontwarn rx.**
# kotlinx.serialization runtime + generated serializers used to parse responses.
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class kotlinx.serialization.** { *; }
-dontwarn kotlinx.serialization.**
# QuickJS engine used by extractors that deobfuscate links.
-keep class app.cash.quickjs.** { *; }
-dontwarn app.cash.quickjs.**
# androidx.preference: extension source ctors/overrides reference PreferenceScreen
# & friends by type; stripping them breaks class verification at load time.
-keep class androidx.preference.** { *; }
-dontwarn androidx.preference.**
