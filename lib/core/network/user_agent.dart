/// The single User-Agent this app presents.
///
/// Cloudflare binds cf_clearance to the exact User-Agent that solved the
/// challenge, so a clearance earned under one and replayed under another is
/// rejected. The Dart side carried five different strings — and the extension
/// HTTP client carried none at all, which means dart:io stamped
/// `Dart/3.x (dart:io)` on every request an extension made. Cloudflare and
/// plenty of ordinary WAFs refuse that outright.
///
/// The Android TV app had the same disease and the same cure.
const String kSozoUserAgent =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
