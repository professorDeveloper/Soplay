/// MyAnimeList OAuth and API endpoints.
///
/// Sozo's MAL app is registered as a PUBLIC client (App Type "android"), so MAL
/// issues a client id and no secret. What protects the code exchange is PKCE —
/// and MAL supports only `code_challenge_method=plain`, meaning the challenge
/// IS the verifier, sent twice.
///
/// That is precisely why the authorize URL is NOT built here: with `plain`, the
/// verifier is the only thing standing between an intercepted code and a token,
/// so it must never be minted or held by the client. The app asks the backend
/// for the URL, the backend keeps the verifier against the Sozo account, and
/// the backend performs the exchange — which also makes the MAL link belong to
/// the ACCOUNT, so a TV inherits it without a second sign-in.
class MalConstants {
  const MalConstants._();

  static const String apiBase = 'https://api.myanimelist.net/v2';

  /// Registered on the MAL client. The `sozo` scheme is already declared by
  /// both platforms (AndroidManifest `<data android:scheme="sozo"/>` and the
  /// iOS `CFBundleURLSchemes`), so the browser hands control straight back.
  static const String redirectUri = 'sozo://mal';

  /// The deeplink host carrying the OAuth result: `sozo://mal?code=...`.
  static const String callbackHost = 'mal';
}

class MalException implements Exception {
  const MalException(this.message);

  final String message;

  @override
  String toString() => message;
}
