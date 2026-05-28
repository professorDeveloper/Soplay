# Dailymotion HLS 403 — server-side fix

## Symptom

Mobil ilovada animexin (yoki boshqa Dailymotion embed ishlatadigan)
provayder orqali video ochilganda quyidagicha xato chiqadi:

```
[PLAYER] loading url: https://cdndirector.dailymotion.com/cdn/manifest/video/<id>.m3u8?sec=...&dmTs=...&dmV1st=...
E/ExoPlayerImplInternal: Source error
  Caused by: androidx.media3.datasource.HttpDataSource$InvalidResponseCodeException: Response code: 403
```

Mobil tomondan `User-Agent`, `Referer: https://www.dailymotion.com/`,
`Origin: https://www.dailymotion.com` headerlari yuborilmoqda, lekin CDN
baribir 403 qaytaradi.

## Sabab

Dailymotion `cdndirector.dailymotion.com` orqali ulashayotgan m3u8 URL
HMAC asosida imzolangan (`sec=` parametri) va imzo quyidagilarga bog‘lab
generatsiya qilinadi:

1. **Foydalanuvchi IP-manzili** — imzo `/embed` yoki `/player/metadata`
   so‘rovi qaysi IP'dan kelgan bo‘lsa, manifestni o‘sha IP'dan o‘qishni
   talab qiladi.
2. **`dmTs` va `dmV1st` qiymatlari** — vaqt mohri va birinchi-ko‘rilgan
   token. `metadata` javobi bilan birga keladi va boshqa sessiyada
   ishlamaydi.
3. **Sessiya cookilari** (`ts`, `v1st`, `dmvk`) — `/embed` sahifasidan
   o‘rnatiladi. Mobil tomon `[fetch] X GET .../embed/...` xatosi tufayli
   bularni saqlay olmayotgan edi; bu hozir `SafeCookieManager` orqali
   tuzatildi.

Hozir bizning extractor pipeline'imiz:

- backendda `/extractors/animexin-video` chaqirilmoqda (logda
  `[HTTP] ← 200 GET /extractors/animexin-video`).
- backend animexin sahifasini olib, dailymotion embedlarni topib
  qaytarmoqda.
- so‘ng mobil JS extractor `dailymotion.com/embed/...` va
  `/player/metadata/...` ga **mobil IP'dan** murojaat qilmoqda.
- shu yerda olingan `sec=`-imzolangan manifest URL **mobil IP'ga**
  bog‘langan bo‘ladi.
- lekin ExoPlayer alohida ulanish ochadi — agar mobil tarmoqda NAT yoki
  IPv6/IPv4 farqi bo‘lsa, IP mos kelmasligi mumkin.
- bundan tashqari `dailymotion.com/embed` so‘rovi mavjud bo‘lgan
  cookie xatosi tufayli muvaffaqiyatsiz tugagan; CDN sessiyani
  tasdiqlay olmay qolgan.

## Tuzilgan mobil-side qism

`lib/core/js/safe_cookie_manager.dart` qo‘shildi.
Dailymotion'ning nostandart `Set-Cookie: ...; Secure=...` qiymatlarini
endi tash­lab yubormaydi va `CookieManagerSaveException` bilan butun
javobni reject qilmaydi. Endi `/embed/...` so‘rovi 200 qaytarib, sessiya
cookilari `CookieJar`ga tushadi va keyingi `/player/metadata` chaqirig‘i
bilan birga avtomatik yuboriladi.

Buni ishlatish:

```dart
Dio(...)..interceptors.add(SafeCookieManager(CookieJar()));
```

## Nima qilish kerak — server tomonida

Cookie fix kifoya qilmasa (test paytida tekshiring: agar log'da
`CookieManagerSaveException` yo‘qolib, lekin 403 davom etsa), CDN imzosi
mobil IP'ga bog‘langan deb hisoblang. Bu holatda quyidagi ikki yo‘ldan
biri tanlanadi:

### 1-variant — Server tomonida HLS proxy (tavsiya etiladi)

`/extractors/animexin-video` allaqachon backendda ishlayotgan ekan,
manifestni va segment chunklarini ham server orqali uzating:

1. Backend `dailymotion.com/embed/<videoId>` va
   `dailymotion.com/player/metadata/video/<videoId>` so‘rovlarini o‘zi
   bajarsin, sessiya cookilarini saqlasin.
2. `sec=`-imzolangan m3u8 URL ham serverda olinsin — shunda imzo
   serverning chiquvchi IP'siga bog‘lanadi.
3. Backend yangi endpoint qo‘shsin, masalan:

   ```
   GET /hls/dailymotion/{videoId}/manifest.m3u8
   GET /hls/dailymotion/{videoId}/segment/{path...}
   ```

4. Manifest javobi qaytarilishidan oldin uning ichidagi nisbiy va to‘liq
   segment URL'lari `/hls/dailymotion/{videoId}/segment/...` ga aylantirib
   yuborilsin (rewrite). Aks holda ExoPlayer chunklarni to‘g‘ridan-to‘g‘ri
   CDN'dan olmoqchi bo‘lib yana 403 yeydi.
5. Segment endpoint kerakli `Referer`, `Origin`, sessiya cookilari va
   `User-Agent` bilan CDN'ga so‘rov yuboradi, javobni `Content-Type` va
   `Cache-Control` headerlarini saqlagan holda streaming qaytaradi.
6. Mobil ilova player URL'ni shu serveriy proxy URL'ga sozlasin.

Eslatma: bu serverda trafik xarajatini bir oz oshiradi, lekin 403
muammosini butunlay yopadi.

### 2-variant — Faqat metadata serverda olinsin, manifest mobilda

Agar trafik oshishi maqbul bo‘lmasa va Dailymotion imzo IP'ni qat'iy
tekshirmasa (oddiy holatda u 1–2 soat ichida o‘sha sessiya doirasida
ishlaydi):

1. Backend `/embed` va `/player/metadata` sahifalarini o‘zi olib,
   serverning `Cookie:` va `dmTs`/`dmV1st`/`sec`-imzolangan URL'ni mobil
   ilovaga qaytarsin.
2. Mobil ilova manifestni to‘g‘ridan-to‘g‘ri CDN'dan ochsin, lekin
   `httpHeaders`ga server bergan `Cookie:` qiymatini ham qo‘shsin.
3. `lib/features/detail/presentation/pages/player_page.dart`
   ichidagi `_initializeWith()` da `httpHeaders` map'ga JS extractor
   qaytargan har qanday `Cookie` field allaqachon `mergedHeaders`'ga
   yuklanadi (`mergedHeaders.addAll(headers)`). Backend response'ga
   `headers: { "Cookie": "ts=...; v1st=...; dmvk=..." }` field qo‘shsa,
   shu yerda avtomatik ishlaydi.

1-variant ishonchli, 2-variant tezroq amalga oshiriladi. Ko‘pchilik
provayderda 1-variant tanlangan — animexin'ni ham shu sxema bilan
uzaytirish maqsadga muvofiq.

## Tekshirish

Mobilda:

```
adb logcat | grep -iE "fetch|PLAYER|ExoPlayer"
```

Quyidagilarni kuting:

- `[fetch] X GET https://www.dailymotion.com/embed/...` qatorlar
  YO‘QOLISHI kerak (cookie fix qilingan).
- `[fetch] ← GET ...embed... (200 ...)` ko‘rinsin.
- `[PLAYER] loading url:` qatori chiqsin va `ExoPlayer Source error`
  YO‘QOLSIN.

Agar `403` davom etsa, server-side proxy variantini qo‘llang.
