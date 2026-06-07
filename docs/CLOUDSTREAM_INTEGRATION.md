# CloudStream plagin integratsiyasi — implementatsiya retsepti (Android-only)

> Maqsad: bir martalik native o'zgartirish bilan istalgan CloudStream repo
> (`repo.json`/`plugins.json` yoki shortcode) dagi `.cs3` plaginlari soplay'da ishlasin.
> Faqat Android. iOS'da bu feature yo'q. Backend tegilmaydi.

## Spike natijasi (tasdiqlangan mexanizm)

CloudStream plaginlari `PathClassLoader(file, context.classLoader)` bilan yuklanadi — ya'ni
**host APK ichida barcha `com.lagradost.cloudstream3.*` runtime sinflari bo'lishi shart**
(`PluginManager.loadPlugin`, recloudstream/cloudstream master).

**Eng muhim soddalashtirish:** runtime'ning deyarli hammasi alohida, **publishable `library`
moduli**da:
- `groupId = com.lagradost.api`, module `library`, KMP (JVM/Android), `maven-publish` yoqilgan.
- Ichida: `MainAPI` (getMainPage/search/load/loadLinks), `object APIHolder` (`allProviders`),
  global `app` HTTP klienti (nicehttp), **112 ta extractor** + `loadExtractor`/`ExtractorApi`,
  `BasePlugin`/`@CloudstreamPlugin`, barcha data-class'lar (LoadResponse/ExtractorLink/…).
- CloudStream `app` moduli = CloudStream'ning UI ilovasi — **bizga KERAK EMAS**.

Plagin yuklash mantig'i (`PluginManager`dan) ~30 qator — uni o'zimiz `PluginHost.kt`da
yozamiz, butun `app` modulini olib kirmaymiz.

### Yuklash mexanizmi (PluginManager.loadPlugin'dan, biz takrorlaymiz)
```kotlin
val loader = PathClassLoader(cs3File.absolutePath, appContext.classLoader)
val manifest = loader.getResourceAsStream("manifest.json").use { parseManifest(it) }
//   manifest: { name, pluginClassName, version, requiresResources, apiVersion? }
val plugin = loader.loadClass(manifest.pluginClassName)
    .getDeclaredConstructor().newInstance() as BasePlugin
plugin.filename = cs3File.absolutePath
plugin.load(appContext)                 // → registerMainAPI(...) → APIHolder.allProviders
// (requiresResources bo'lsa AssetManager.addAssetPath bilan resources beriladi — Plugin.resources)
```
Ro'yxatga olingan provayderlar: `com.lagradost.cloudstream3.APIHolder.allProviders` (List<MainAPI>).

## 1-bosqich — runtime'ni ulash (Android Studio'da)

`settings.gradle.kts` → `dependencyResolutionManagement { repositories { ... maven("https://jitpack.io") } }`
`android/app/build.gradle.kts`:
```kotlin
dependencies {
    // Variant A (TAVSIYA, tasdiqlangan): JitPack'dagi `library` submoduli.
    // JitPack `pre-release` ref'ni MUVAFFAQIYATLI build qiladi (tekshirildi:
    // jitpack.io/api/builds/com.github.recloudstream/cloudstream → "pre-release":"ok").
    // Subproject koordinata sintaksisi: com.github.<user>.<repo>:<module>:<ref>
    implementation("com.github.recloudstream.cloudstream:library:pre-release")
    // Plaginlar (phisher/redowan) ham `pre-release`ga kompilyatsiya qilingani uchun
    // apiVersion mos keladi.

    // Variant B (zaxira): recloudstream/cloudstream ni git submodule qilib, :library
    // modulini includeBuild/module sifatida ulash → implementation(project(":library"))
}
```
> **Build paytida tasdiqlanadi:** koordinata resolve bo'lishi (JitPack birinchi marta build
> qilishi 1-2 daq), transitiv bog'liqliklar (nicehttp/jackson/jsoup/rhino/newpipe/tmdb-java/
> fuzzywuzzy) kelishi, va bitta `.cs3` (phisher HDhub4u) yuklanib `APIHolder.allProviders`ga
> tushishi. Agar `pre-release` apiVersion mos kelmasa — `c4ccc5d351`/`444a72dbf6`/`6ff64637b6`
> (JitPack "ok") yoki boshqa tag sinaladi.

`PluginHost.kt` skeleti shu papkada: `android/app/src/main/kotlin/com/soplay/sozo/cloudstream/`
(quyidagi "Skelet" bo'limiga qarang). 1-bosqich testi: bitta `.cs3` (masalan phisher HDhub4u)
ni yuklab, `getMainPage`/`load`/`loadLinks` ni Logcat'da tekshirish.

## 2-bosqich — MethodChannel + Flutter
- `MainActivity.kt`'da `MethodChannel("soplay/cloudstream")` (mavjud `soplay/pip`,`soplay/downloads`
  namunasi). Metodlar: `addRepo/removeRepo/listRepos`, `listProviders`, `getMainPage`, `search`,
  `load`, `loadLinks`. CloudStream `suspend` funksiyalari → `CoroutineScope(Dispatchers.IO)` →
  `result.success(json)`.
- Flutter: `lib/core/cloudstream/cloudstream_channel.dart` (Platform.isAndroid bilan o'ralgan).

## 3-bosqich — repo + shortcode + UI
- **repo.json** formati: `{ name, iconUrl, description, pluginLists:[url...] }` → har `pluginLists`
  URL = **plugins.json** (massiv): `[{name, internalName, url(.cs3), version, apiVersion, tvTypes,
  language, iconUrl, ...}]`.
- **shortcode**: `https://l.cloudstream.app/<code>` → redirect → repo.json (yoki CloudStream
  shortcode API). Kod ham, to'g'ridan-to'g'ri URL ham qabul qilinadi.
- "Manba qo'shish" UI (Android'da) + lokal saqlash (Hive/shared_prefs) + `.cs3` keshi
  (`filesDir/cs3/<internalName>@<version>.cs3`, versiya bo'yicha invalidatsiya).

## Mavjud modelga moslash (dizaynga TEGMASLIK)
- **Card** → mavjud provider-card modeli (`{provider:'cs:'+name, externalId, title, contentUrl,
  thumbnail, year, ...}`).
- **load()** (`LoadResponse`) → mavjud detail + episodes entity.
- **loadLinks** (`ExtractorLink`) → mavjud `VideoSourceEntity {videoUrl, headers(referer+headers),
  quality, type:'hls'|'http'}`; `SubtitleFile` → mavjud subtitle entity.
- Player (`video_player`/`player_page.dart`) o'zgarmaydi (url + httpHeaders + VideoFormat.hls).

## my-list / davom ettirish (BUZILMASIN)
- Barqaror id sxemasi: `provider = "cs:<internalName>"`, `contentUrl/contentId` = plagin `load`
  url'i (barqaror). my-list/continue-watching shu `provider+contentId+contentUrl` ga tayanadi —
  shu maydonlar to'ldirilsa, qo'shish/o'qish/davom ettirish ishlaydi. Regress testi shart.

## Gating / risk
- Hamma CloudStream chaqiruvi `Platform.isAndroid` bilan; iOS'da provayderlar ro'yxatga qo'shilmaydi.
- ProGuard: `-keep class com.lagradost.cloudstream3.** { *; }` va yuklangan plagin sinflari.
- GPL-3.0 (qabul qilingan): tarqatishda manba ochiq. Play Store o'rniga APK/sideload tavsiya.
- apiVersion drift: ba'zi plaginlar yangi/eski API talab qilishi mumkin — library versiyasini
  maqsad repolarga moslab tanlaymiz.

## Hozircha holat
Spike (mexanizm + library kashfiyoti) tugadi. Keyingi qadam — Android Studio'da `library`ni ulab
build qilish (koordinata + apiVersion'ni amalda tasdiqlash), so'ng bitta `.cs3` yuklab Logcat testi.
Bu qadamlar real Android build talab qiladi.
