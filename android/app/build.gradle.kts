import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// 1. Keystore ma'lumotlarini yuklash
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("app/key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.soplay.sozo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
        // Vendored Aniyomi OkHttpExtensions.parseAs uses context receivers.
        freeCompilerArgs += "-Xcontext-receivers"
    }

    defaultConfig {
        applicationId = "com.soplay.sozo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 2. Raqamli imzo sozlamalarini yaratish
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // 3. Debug imzosini "release" imzosiga almashtirish
            signingConfig = signingConfigs.getByName("release")

            // Ilovani optimizatsiya qilish (R8 + resurs siqish)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
    // CloudStream's library pulls okhttp5 + jspecify etc., which collide on some
    // META-INF resources. Drop the duplicates so packaging succeeds.
    packaging {
        resources {
            excludes += setOf(
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
                "META-INF/DEPENDENCIES",
                "META-INF/INDEX.LIST",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/LICENSE.md",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/NOTICE.md",
                "META-INF/{AL2.0,LGPL2.1}",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // CloudStream provider runtime (Android-only feature). The `library` module
    // carries MainAPI/APIHolder/`app` HTTP client/extractors/BasePlugin so .cs3
    // plugins load against it. Resolves on JitPack (POM/module/jar verified at
    // v4.7.0; Gradle picks the KMP android variant via .module). See
    // docs/CLOUDSTREAM_INTEGRATION.md + cloudstream/PluginHost.kt.
    implementation("com.github.recloudstream.cloudstream:library:v4.7.0")
    // CloudStream plugins/extractors use coroutines on the IO dispatcher.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // compileOnly: lets our clean-room CloudflareKiller implement okhttp3.Interceptor.
    // okhttp itself is supplied at runtime by the CloudStream `library` above (it's
    // `implementation`-scoped there, so it isn't on our compile classpath). The
    // Interceptor/Response/Headers APIs used are stable across okhttp 4.x/5.x.
    compileOnly("com.squareup.okhttp3:okhttp:4.12.0")

    // Aniyomi extension runtime (Android-only). Extension APKs compile against the
    // stub `extensions-lib` as compileOnly, so the host app must supply the real
    // runtime + these libraries at DexClassLoader time. See docs/ANIYOMI_INTEGRATION.md.
    implementation("org.jetbrains.kotlin:kotlin-reflect:2.2.20")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.7.3")
    implementation("org.jsoup:jsoup:1.18.1")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("androidx.preference:preference-ktx:1.2.1")
    // JS engine for Aniyomi extractors that deobfuscate links (QuickJS).
    implementation("app.cash.quickjs:quickjs-android:0.9.2")
}