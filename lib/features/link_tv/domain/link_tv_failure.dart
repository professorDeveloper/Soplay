/// A pairing failure the UI can render without string-matching the backend.
///
/// The API's entire error contract is a bare `{"message": "<uzbek text>"}` whose
/// meaning lives in the HTTP status, so the status is translated into a stable
/// [messageKey] here and the raw [serverMessage] is kept only as a fallback for
/// the codes we do not model.
class LinkTvFailure implements Exception {
  /// An easy_localization key, or null when only [serverMessage] is available.
  final String? messageKey;
  final String? serverMessage;

  const LinkTvFailure({this.messageKey, this.serverMessage});

  @override
  String toString() => messageKey ?? serverMessage ?? 'link_tv.error_generic';
}
