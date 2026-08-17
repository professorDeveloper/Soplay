/// AniList OAuth and API endpoints.
///
/// This app uses the AUTHORIZATION CODE flow, not the implicit one. The browser
/// hands back a short-lived code, the app posts that code to our backend, and
/// the backend — which holds the client secret — exchanges it for a token and
/// stores it against the Sozo account.
///
/// That indirection buys two things worth the extra hop:
///   * the client secret never ships inside a mobile binary, where it could not
///     stay secret anyway;
///   * the AniList link belongs to the ACCOUNT, so the TV inherits it without a
///     second sign-in on a device that is painful to type on.
///
/// The client id is public by design — it identifies the app in an authorize URL
/// the user's own browser opens, and AniList treats it as such.
class AnilistConstants {
  const AnilistConstants._();

  static const String clientId = '48803';

  /// Registered on the AniList client. Both platforms already declare the
  /// `sozo` scheme (AndroidManifest `<data android:scheme="sozo"/>` and the
  /// iOS `CFBundleURLSchemes`), so the browser hands control straight back.
  static const String redirectUri = 'sozo://anilist';

  static const String graphqlEndpoint = 'https://graphql.anilist.co';

  /// `response_type=code` returns the code in the QUERY string of the redirect.
  /// The implicit flow would have returned a token in the URL fragment instead,
  /// which app_links does not surface through `queryParameters` — a difference
  /// worth stating, because it fails silently rather than loudly.
  static Uri authorizeUrl() => Uri.parse(
    'https://anilist.co/api/v2/oauth/authorize'
    '?client_id=$clientId'
    '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
    '&response_type=code',
  );

  /// The deeplink host carrying the OAuth result: `sozo://anilist?code=...`.
  static const String callbackHost = 'anilist';
}
