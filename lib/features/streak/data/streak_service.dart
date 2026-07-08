import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/streak/data/streak_remote_data_source.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';

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

  String _timezone() => DateTime.now().timeZoneName;
  int _tzOffset() => DateTime.now().timeZoneOffset.inMinutes;

  String _todayLocal() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  Future<void> refresh() async {
    if (!_hive.isLoggedIn || _refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final fresh = await _remote.getMe(_timezone(), _tzOffset());
      state.value = fresh;
      await _writeCache(fresh);
    } catch (_) {
    } finally {
      _refreshInFlight = false;
    }
  }

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
