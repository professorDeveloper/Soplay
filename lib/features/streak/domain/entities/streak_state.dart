class StreakState {
  final int current;
  final int longest;
  final String? lastActiveDate;
  final bool pingedToday;
  final bool isAtRisk;

  const StreakState({
    required this.current,
    required this.longest,
    this.lastActiveDate,
    this.pingedToday = false,
    this.isAtRisk = false,
  });

  static const empty = StreakState(current: 0, longest: 0);

  StreakState copyWith({
    int? current,
    int? longest,
    String? lastActiveDate,
    bool? pingedToday,
    bool? isAtRisk,
  }) =>
      StreakState(
        current: current ?? this.current,
        longest: longest ?? this.longest,
        lastActiveDate: lastActiveDate ?? this.lastActiveDate,
        pingedToday: pingedToday ?? this.pingedToday,
        isAtRisk: isAtRisk ?? this.isAtRisk,
      );

  Map<String, dynamic> toJson() => {
        'current': current,
        'longest': longest,
        'lastActiveDate': lastActiveDate,
        'pingedToday': pingedToday,
        'isAtRisk': isAtRisk,
      };

  factory StreakState.fromJson(Map<String, dynamic> json) => StreakState(
        current: (json['current'] as num?)?.toInt() ?? 0,
        longest: (json['longest'] as num?)?.toInt() ?? 0,
        lastActiveDate: json['lastActiveDate'] as String?,
        pingedToday: json['pingedToday'] as bool? ?? false,
        isAtRisk: json['isAtRisk'] as bool? ?? false,
      );
}

class StreakPingResult {
  final StreakState state;
  final int? newMilestone;

  const StreakPingResult({required this.state, this.newMilestone});

  factory StreakPingResult.fromJson(Map<String, dynamic> json) {
    final ms = json['isNewMilestone'];
    return StreakPingResult(
      state: StreakState.fromJson(json),
      newMilestone: ms is num ? ms.toInt() : null,
    );
  }
}
