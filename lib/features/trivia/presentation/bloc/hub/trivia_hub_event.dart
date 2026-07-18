import 'package:equatable/equatable.dart';

sealed class TriviaHubEvent extends Equatable {
  const TriviaHubEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the hub — fetches the daily-rank teaser.
class TriviaHubStarted extends TriviaHubEvent {
  const TriviaHubStarted();
}

/// Pull-to-refresh / re-enter — re-fetches the daily-rank teaser.
class TriviaHubRefreshed extends TriviaHubEvent {
  const TriviaHubRefreshed();
}
