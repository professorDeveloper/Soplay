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
