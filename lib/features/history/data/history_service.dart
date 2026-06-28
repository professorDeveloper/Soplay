import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';

class HistoryService {
  static const int _maxItems = 50;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Box get _box => Hive.box(AppConstants.historyBox);

  List<HistoryItem> getAll() {
    final items = <HistoryItem>[];
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is String) {
          items.add(
            HistoryItem.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        }
      } catch (_) {}
    }
    items.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return items;
  }

  HistoryItem? get(String contentUrl, {int? episodeIndex, int? episodeNumber}) {
    final key = HistoryItem.buildStorageKey(
      contentUrl: contentUrl,
      isSerial: episodeIndex != null || episodeNumber != null,
      episodeIndex: episodeIndex,
      episodeNumber: episodeNumber,
    );
    final raw = _box.get(key) ?? _box.get(contentUrl);
    if (raw is String) {
      try {
        return HistoryItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (episodeIndex == null && episodeNumber == null) {
      return _getLatestForContent(contentUrl);
    }
    return null;
  }

  HistoryItem? _getLatestForContent(String contentUrl) {
    final prefix = '$contentUrl::episode::';
    HistoryItem? latest;
    for (final key in _box.keys) {
      if (key is! String || !key.startsWith(prefix)) continue;
      try {
        final raw = _box.get(key);
        if (raw is! String) continue;
        final item =
            HistoryItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (latest == null || item.watchedAt > latest.watchedAt) {
          latest = item;
        }
      } catch (_) {}
    }
    return latest;
  }

  Future<void> save(HistoryItem item) async {
    // Items the user moved to their Private list must leave no history trail.
    if (getIt.isRegistered<PrivateListService>() &&
        getIt<PrivateListService>().contains(item.contentUrl)) {
      return;
    }
    await _box.put(item.storageKey, jsonEncode(item.toJson()));
    await _trimIfNeeded();
    revision.value++;
  }

  Future<void> remove(String key) async {
    await _box.delete(key);
    revision.value++;
  }

  /// Removes every history entry for a content url (the base key plus any
  /// `::episode::N` keys). Used when an item is moved to the Private list so no
  /// trace of it remains in the history.
  Future<void> removeByContentUrl(String contentUrl) async {
    final keys = _box.keys
        .whereType<String>()
        .where((k) => k == contentUrl || k.startsWith('$contentUrl::'))
        .toList();
    for (final k in keys) {
      await _box.delete(k);
    }
    if (keys.isNotEmpty) revision.value++;
  }

  Future<void> clearAll() async {
    await _box.clear();
    revision.value++;
  }

  Future<void> _trimIfNeeded() async {
    if (_box.length <= _maxItems) return;
    final items = getAll();
    if (items.length <= _maxItems) return;
    final toRemove = items.sublist(_maxItems);
    for (final item in toRemove) {
      await _box.delete(item.storageKey);
    }
  }
}
