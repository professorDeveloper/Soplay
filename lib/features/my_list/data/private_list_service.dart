import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/my_list/data/models/favorite_model.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';

/// Local-only storage for the LOCKED PRIVATE LIST.
///
/// Mirrors [HistoryService]/[MyListLocalDataSource]: a GetIt singleton over a
/// dedicated Hive box ([AppConstants.privateFavoritesBox]) that stores
/// JSON-String [FavoriteModel] values keyed by `contentUrl`, and exposes a
/// [revision] notifier so UIs can rebuild when the private set changes.
///
/// On top of storage it carries an in-memory SESSION gate ([isUnlockedForSession])
/// that is NEVER persisted: the list starts locked on every cold start and is
/// only opened after the user passes the app-lock PIN/biometric flow.
class PrivateListService {
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _unlocked = false;

  /// Whether the private list has been unlocked during this app session.
  bool get isUnlockedForSession => _unlocked;

  /// Marks the private list as unlocked for the remainder of this session.
  void markUnlocked() => _unlocked = true;

  /// Re-locks the private list (e.g. on logout / app background, if wired).
  void lock() => _unlocked = false;

  Box get _box => Hive.box(AppConstants.privateFavoritesBox);

  /// All private items, newest first (by `addedAt`).
  List<FavoriteEntity> getAll() {
    final items = <FavoriteModel>[];
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is String) {
          items.add(
            FavoriteModel.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        }
      } catch (_) {}
    }
    items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return items;
  }

  bool contains(String contentUrl) => _box.containsKey(contentUrl);

  Future<void> add(FavoriteEntity e) async {
    final model = FavoriteModel(
      provider: e.provider,
      contentUrl: e.contentUrl,
      title: e.title,
      thumbnail: e.thumbnail,
      description: e.description,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _box.put(e.contentUrl, jsonEncode(model.toJson()));
    revision.value++;
  }

  Future<void> remove(String contentUrl) async {
    await _box.delete(contentUrl);
    revision.value++;
  }

  Future<void> clearAll() async {
    await _box.clear();
    revision.value++;
  }
}
