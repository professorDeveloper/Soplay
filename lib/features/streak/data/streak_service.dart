import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/streak/data/streak_remote_data_source.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';

/// Single source of truth for the user's daily watch streak.
///
/// - `state` is a ValueNotifier widgets can listen to without a Bloc.
/// - The last known state is mirrored in Hive so the badge stays populated
///   while the app is offline / before the first `/me` round-trip.
/// - `ping()` is debounced to once per app session — calling it from the
///   60-second watch hook is safe to repeat.
class StreakService {
  StreakService({
    required StreakRemoteDataSource remote,
    required HiveService hive,
  })  : _remote = remote,
        _hive = hive {
    state.value = _readCache();
  }

  final StreakRemoteDataSource _remote;
  final HiveService _hive;

  final ValueNotifier<StreakState> state =
      ValueNotifier<StreakState>(StreakState.empty);
  final StreamController<int> milestones = StreamController<int>.broadcast();

  // The local calendar day (yyyy-mm-dd) of the last *successful* ping. Debounces
  // to one ping per day rather than one per app process, so a long-lived app that
  // crosses midnight still records the new day. Null = not pinged yet this run.
  String? _lastPingDay;
  bool _refreshInFlight = false;

  Box get _box => Hive.box(AppConstants.streakBox);

  StreakState _readCache() {
    try {
      final raw = _box.get(AppConstants.streakStateKey);
      if (raw is String && raw.isNotEmpty) {
        return StreakState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return StreakState.empty;
  }

  Future<void> _writeCache(StreakState s) async {
    try {
      await _box.put(AppConstants.streakStateKey, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  // A best-effort zone name (for storage/debug) plus the reliable part: the UTC
  // offset in minutes (e.g. +300 for UTC+5). The backend does its day/hour math
  // from the offset because `timeZoneName` is a non-IANA OS string on every
  // platform (Windows "West Asia Standard Time", Android "GMT+05:00", …).
  String _timezone() => DateTime.now().timeZoneName;
  int _tzOffset() => DateTime.now().timeZoneOffset.inMinutes;

  String _todayLocal() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  /// Fetch the latest state from the backend. Safe to call eagerly; if not
  /// logged in or the call fails the cached state is kept.
  Future<void> refresh() async {
    if (!_hive.isLoggedIn || _refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final fresh = await _remote.getMe(_timezone(), _tzOffset());
      state.value = fresh;
      await _writeCache(fresh);
    } catch (_) {
      // Network/auth issues are non-fatal — keep showing cached state.
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Mark "watched today". Debounced to once per local calendar day (not once
  /// per process), so a session that spans midnight records the next day too.
  /// Returns the new milestone (e.g. 7) when the user just crossed one.
  Future<int?> ping() async {
    if (!_hive.isLoggedIn) return null;
    final today = _todayLocal();
    if (_lastPingDay == today) return null;
    try {
      final result = await _remote.ping(_timezone(), _tzOffset());
      _lastPingDay = today;
      state.value = result.state;
      await _writeCache(result.state);
      if (result.newMilestone != null && !milestones.isClosed) {
        milestones.add(result.newMilestone!);
      }
      return result.newMilestone;
    } catch (_) {
      // Leave _lastPingDay unset so a later watch this day can retry.
      return null;
    }
  }

  void reset() {
    _lastPingDay = null;
    state.value = StreakState.empty;
    _box.delete(AppConstants.streakStateKey).catchError((_) {});
  }

  void dispose() {
    state.dispose();
    milestones.close();
  }
}
