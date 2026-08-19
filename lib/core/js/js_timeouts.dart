/// How long an extension call may take before the app stops waiting on it.
///
/// Nothing in either JS runtime was bounded, so a source that never answered
/// left the screen it was loading on its skeleton indefinitely. Generous rather
/// than tight: a single call can legitimately be several requests plus a
/// Cloudflare solve, and cutting a slow-but-working source off reads as the
/// same bug from the other side.
const Duration kJsCallTimeout = Duration(seconds: 40);
