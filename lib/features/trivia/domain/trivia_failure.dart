/// A trivia API failure that keeps the HTTP status alongside the message.
///
/// A bare `Exception(message)` cannot tell 409 ("this actor has too few
/// approved clips") from 500, which forced the game screen to print the
/// server's English sentence into an Uzbek UI. Carrying [status] lets the bloc
/// classify the failure and the UI render a localized, honest message.
class TriviaFailure implements Exception {
  const TriviaFailure({required this.message, this.status});

  /// HTTP status of the failed response, or null for transport-level errors.
  final int? status;
  final String message;

  /// The server refuses to build a round: not enough approved clips.
  bool get isNotEnoughClips => status == 409;

  @override
  String toString() => message;
}
