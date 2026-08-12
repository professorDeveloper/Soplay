import 'package:flutter/foundation.dart';
import 'package:riasdxd/core/navigation/app_tab.dart';

class NavController {
  final _index = ValueNotifier<int>(0);

  ValueListenable<int> get index => _index;

  /// Set by MainPage: current visible index of a [TabId], or -1 if hidden.
  int Function(TabId id)? tabIndexResolver;

  void goTo(int tab) => _index.value = tab;

  /// Jump to a tab by identity. Returns false if the tab isn't in the visible
  /// set — the caller may then fall back to pushing the feature's route.
  bool goToId(TabId id) {
    final i = tabIndexResolver?.call(id) ?? -1;
    if (i < 0) return false;
    _index.value = i;
    return true;
  }

  /// "Am I the visible tab?" guard, id-based (replaces `index.value == 3`).
  bool isActive(TabId id) => _index.value == (tabIndexResolver?.call(id) ?? -1);
}
