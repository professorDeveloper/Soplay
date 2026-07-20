I now have everything verified. Here is the complete architecture.

---

# soplay — Customizable Bottom Navigation: complete buildable architecture

Verified against real code: `main_page.dart` (871 lines, tabs at 161-170, metadata `_SoplayGlassCapsule._items` at 333-359, 3 nav renderers), `nav_controller.dart` (9 lines, just `goTo(int)`), `nav_prefs.dart` (navStyle ValueNotifier), `hive_service.dart:262-269` (navStyle get/set on `_settingsBox`), `profile_page.dart` `_AppearanceSection` (1907-2090, `_setNavStyle`/`_navSegment`/`_SectionCard`), the 5 magic-index call sites, and `assets/translations/en.json:286-293` (`navigation.*` block, `downloads` already present).

## 0. Design decisions (grounded in the two studies)

| Decision | Choice for soplay | Why |
|---|---|---|
| Count rule | **4–6, any count** (not satashkent's strict "2 or 4") | soplay's liquid-glass bar/pill has **no center FAB notch** — no even-split geometry to satisfy. Relax `_validCount` to `>= kMinTabs && <= kMaxTabs`. |
| Fixed anchors | **Home + Profile are `mandatory`** (can't be removed; order still free) | Bar can never be emptied; Profile hosts Settings/Appearance (the customizer itself) so it must stay reachable. This is satashkent's "Home is special" invariant, generalized. |
| State model | **`List<TabId>` persisted; registry is source of truth** | Ports satashkent's "store ids only" model. Merges soplay's two parallel lists (body 161-170 + metadata 333-359) into one registry — the core fix flagged in the app_nav study §4.4. |
| Live update | **`NavPrefs.tabOrder` ValueNotifier**, mirrored from Hive | Exact clone of the existing `NavPrefs.navStyle` plumbing — the editor lives in the Profile tab, a sibling of the nav inside the same shell, so a plain rebuild can't reach it. |
| No dedicated controller | Use `NavPrefs` + `HiveService` + a `sanitizeTabOrder()` fn | soplay already has the notifier→Hive pattern; a separate `QuickNavController` ChangeNotifier would be redundant machinery. `sanitizeTabOrder` carries satashkent's `_sanitize` safety. |
| Desktop | Untouched behavior; `_SoplayFloatingNav` pill renders the same dynamic `items` | Requirement: must not break desktop. Same registry feeds all 3 renderers. |

---

## 1. Tab registry model — NEW FILE `lib/core/navigation/app_tab.dart`

This merges the body `List<Widget>` and the metadata `_NavItem` list into one authoritative map, and carries the min/max/mandatory/sanitize logic.

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';

import 'package:soplay/features/home/presentation/pages/home_page.dart';
import 'package:soplay/features/search/presentation/pages/search_page.dart';
import 'package:soplay/features/shorts/presentation/pages/shorts_page.dart';
import 'package:soplay/features/my_list/presentation/pages/my_list_page.dart';
import 'package:soplay/features/profile/presentation/pages/profile_page.dart';
// Optional feature tabs — already-shipped pages (verified paths/const ctors):
import 'package:soplay/features/download/presentation/pages/downloads_page.dart';
import 'package:soplay/features/history/presentation/pages/history_page.dart';
import 'package:soplay/features/tracker/presentation/pages/following_page.dart';

/// Stable, persisted key for every navigable tab. Add a value here + one
/// registry entry + a `navigation.<name>` translation to introduce a new tab
/// (Premiere, Kino Billar, ...). `.name` is what gets stored in Hive.
enum TabId { home, search, shorts, myList, profile, downloads, history, following }

/// Per-tab runtime state only the shell can supply. Shorts needs to know whether
/// it is the visible tab (autoplay pause) and the refresh tick; every other
/// builder ignores it.
class TabBuildContext {
  const TabBuildContext({required this.isActive, required this.shortsRefreshTick});
  final bool isActive;
  final int shortsRefreshTick;
}

typedef TabPageBuilder = Widget Function(TabBuildContext ctx);

class AppTabDef {
  const AppTabDef({
    required this.id,
    required this.icon,
    required this.activeIcon,
    required this.labelKey,
    required this.builder,
    this.mandatory = false,
  });

  final TabId id;
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;      // easy_localization key, e.g. 'navigation.home'
  final TabPageBuilder builder;
  final bool mandatory;       // cannot be removed in the customizer
}

// Top-level builders so the registry map can stay `const` (tear-offs are const).
Widget _homeBuilder(TabBuildContext _) => const HomePage();
Widget _searchBuilder(TabBuildContext _) => const SearchPage();
Widget _shortsBuilder(TabBuildContext c) =>
    ShortsPage(active: c.isActive, refreshTick: c.shortsRefreshTick);
Widget _myListBuilder(TabBuildContext _) => const MyListPage();
Widget _profileBuilder(TabBuildContext _) => const ProfilePage();
Widget _downloadsBuilder(TabBuildContext _) => const DownloadsPage();
Widget _historyBuilder(TabBuildContext _) => const HistoryPage();
Widget _followingBuilder(TabBuildContext _) => const FollowingPage();

/// Single source of truth — replaces the old body list (main_page 161-170) AND
/// the metadata list (_SoplayGlassCapsule._items 333-359).
const Map<TabId, AppTabDef> kTabRegistry = {
  TabId.home: AppTabDef(
    id: TabId.home, icon: CupertinoIcons.house, activeIcon: CupertinoIcons.house_fill,
    labelKey: 'navigation.home', mandatory: true, builder: _homeBuilder),
  TabId.search: AppTabDef(
    id: TabId.search, icon: CupertinoIcons.search, activeIcon: CupertinoIcons.search,
    labelKey: 'navigation.search', builder: _searchBuilder),
  TabId.shorts: AppTabDef(
    id: TabId.shorts, icon: CupertinoIcons.play_rectangle,
    activeIcon: CupertinoIcons.play_rectangle_fill,
    labelKey: 'navigation.shorts', builder: _shortsBuilder),
  TabId.myList: AppTabDef(
    id: TabId.myList, icon: CupertinoIcons.bookmark, activeIcon: CupertinoIcons.bookmark_fill,
    labelKey: 'navigation.my_list', builder: _myListBuilder),
  TabId.profile: AppTabDef(
    id: TabId.profile, icon: CupertinoIcons.person, activeIcon: CupertinoIcons.person_fill,
    labelKey: 'navigation.profile', mandatory: true, builder: _profileBuilder),
  // ---- optional, opt-in via the customizer ----
  TabId.downloads: AppTabDef(
    id: TabId.downloads, icon: CupertinoIcons.cloud_download,
    activeIcon: CupertinoIcons.cloud_download_fill,
    labelKey: 'navigation.downloads', builder: _downloadsBuilder),
  TabId.history: AppTabDef(
    id: TabId.history, icon: CupertinoIcons.clock, activeIcon: CupertinoIcons.clock_fill,
    labelKey: 'navigation.history', builder: _historyBuilder),
  TabId.following: AppTabDef(
    id: TabId.following, icon: CupertinoIcons.heart, activeIcon: CupertinoIcons.heart_fill,
    labelKey: 'navigation.following', builder: _followingBuilder),
};

/// Default = the current shipped 5-tab order → this IS the back-compat contract.
const List<TabId> kDefaultTabs = [
  TabId.home, TabId.search, TabId.shorts, TabId.myList, TabId.profile,
];

const int kMinTabs = 4;
const int kMaxTabs = 6;

TabId? tabIdFromKey(String key) {
  for (final id in TabId.values) {
    if (id.name == key) return id;
  }
  return null;
}

Set<TabId> mandatoryTabs() =>
    {for (final e in kTabRegistry.entries) if (e.value.mandatory) e.key};

/// Ported from satashkent's `_sanitize`. Runs on BOTH read and save so a stale
/// or corrupt Hive value can never break the bar:
///  - drops unknown ids (registry shrank between versions) & de-dupes
///  - force-includes any missing mandatory tab (never lose Home/Profile)
///  - tops up to kMinTabs from defaults, clamps down to kMaxTabs
///  - empty → defaults
List<TabId> sanitizeTabOrder(List<String> raw) {
  final out = <TabId>[];
  for (final k in raw) {
    final id = tabIdFromKey(k);
    if (id != null && kTabRegistry.containsKey(id) && !out.contains(id)) out.add(id);
  }
  for (final id in kDefaultTabs) {
    if (mandatoryTabs().contains(id) && !out.contains(id)) out.add(id);
  }
  if (out.length < kMinTabs) {
    for (final id in kDefaultTabs) {
      if (!out.contains(id)) out.add(id);
      if (out.length >= kMinTabs) break;
    }
  }
  if (out.isEmpty) return List.of(kDefaultTabs);
  return out.length > kMaxTabs ? out.take(kMaxTabs).toList() : out;
}

List<String> encodeTabOrder(List<TabId> ids) => [for (final id in ids) id.name];
```

---

## 2. Hive persistence — EDIT `lib/core/storage/hive_service.dart`

Add next to the existing `navStyle` methods (after line 269), same `_settingsBox`, raw untyped `List<String>` (no adapter — satashkent's exact pattern):

```dart
// Bottom-nav tab set + order (list of TabId.name strings). Absent key ⇒ the
// current shipped 5 tabs ⇒ existing users see an identical bar (back-compat).
List<String> get tabOrder {
  final v = _settingsBox.get('tab_order');
  if (v is List) return v.map((e) => e.toString()).toList();
  return const ['home', 'search', 'shorts', 'myList', 'profile'];
}

Future<void> setTabOrder(List<String> ids) => _settingsBox.put('tab_order', ids);
```

**Hive keys:** box = existing settings box (same one holding `'nav_style'`), key = **`'tab_order'`**, value = `List<String>` of `TabId.name`.

---

## 3. NavPrefs — EDIT `lib/core/system/nav_prefs.dart`

Add a second notifier mirroring `navStyle` (keep the default as literal strings to avoid pulling the heavy `app_tab.dart` page-imports into `core/system`):

```dart
/// Persisted tab set/order (list of TabId.name). Instant-rebuild reason is the
/// same as navStyle: the customizer lives in the Profile tab, a sibling of the
/// nav inside the same shell. Default = current shipped 5 tabs.
static final ValueNotifier<List<String>> tabOrder = ValueNotifier<List<String>>(
  const ['home', 'search', 'shorts', 'myList', 'profile'],
);
```

---

## 4. NavController — EDIT `lib/core/navigation/nav_controller.dart`

Add an id-based API so the magic `goTo(n)` callers stop assuming positions. The shell registers a resolver (it owns the live visible order):

```dart
import 'package:flutter/foundation.dart';
import 'package:soplay/core/navigation/app_tab.dart';

class NavController {
  final _index = ValueNotifier<int>(0);
  ValueListenable<int> get index => _index;

  /// Set by MainPage: current visible index of a TabId, or -1 if it's hidden.
  int Function(TabId id)? tabIndexResolver;

  void goTo(int tab) => _index.value = tab;

  /// Jump to a tab by identity. Returns false if the tab isn't in the visible
  /// set — caller may then fall back to pushing the feature's standalone route.
  bool goToId(TabId id) {
    final i = tabIndexResolver?.call(id) ?? -1;
    if (i < 0) return false;
    _index.value = i;
    return true;
  }

  /// "Am I the visible tab?" guard, id-based (replaces `index.value == 3`).
  bool isActive(TabId id) => _index.value == (tabIndexResolver?.call(id) ?? -1);
}
```

DI registration (`injection.dart:436`) is unchanged — still a plain singleton; the resolver is wired in the shell's `initState`.

---

## 5. Shell rendering — EDIT `lib/features/main/presentation/pages/main_page.dart`

### 5a. State: derive the tab set, de-magic the indices

- **Add import:** `import 'package:soplay/core/navigation/app_tab.dart';`
- **Replace** `static const int _shortsIndex = 2;` with a mutable list + getters:

```dart
List<TabId> _visibleTabs = const [];

int get _shortsIndex => _visibleTabs.indexOf(TabId.shorts);       // -1 if hidden
int get _homeIndex {
  final i = _visibleTabs.indexOf(TabId.home);
  return i < 0 ? 0 : i;
}
```

- **`initState`** (after `_hiveService = getIt<HiveService>();`), mirror Hive → notifier exactly like the existing `NavPrefs.navStyle.value = _hiveService.navStyle;` line, then compute and register the resolver + listener:

```dart
_visibleTabs = sanitizeTabOrder(_hiveService.tabOrder);
NavPrefs.tabOrder.value = _hiveService.tabOrder;
NavPrefs.tabOrder.addListener(_onTabSetChange);
_navController.tabIndexResolver = (id) => _visibleTabs.indexOf(id);
```

- **`dispose`**: `NavPrefs.tabOrder.removeListener(_onTabSetChange);`
- **New handler** — recompute + clamp `_index` (keep the *same tab* selected if it survived, else Home). Kept as a listener (not a wrapping `ValueListenableBuilder`) so the body doesn't remount on unrelated navStyle changes — preserving the "don't re-trigger the Home Telegram sheet" invariant noted at line 217-219:

```dart
void _onTabSetChange() {
  final currentId = (_index >= 0 && _index < _visibleTabs.length)
      ? _visibleTabs[_index]
      : TabId.home;
  final next = sanitizeTabOrder(NavPrefs.tabOrder.value);
  setState(() {
    _visibleTabs = next;
    final keep = next.indexOf(currentId);
    _index = keep >= 0 ? keep : (next.indexOf(TabId.home) < 0 ? 0 : next.indexOf(TabId.home));
  });
  _navController.goTo(_index); // keep the singleton in sync
}
```

- **Guard the Shorts logic** (`_handleTabTap` 124-126, `_refreshShorts` 130, `_maybeShowShortsRefreshTip` 135-148) with `_shortsIndex >= 0`, e.g.:
  - `if (reselected && _shortsIndex >= 0 && index == _shortsIndex) _refreshShorts();`
  - `_refreshShorts`: `if (_shortsIndex < 0 || _index != _shortsIndex) return;`
  - `_maybeShowShortsRefreshTip`: `if (_shortsIndex < 0 || _index != _shortsIndex || ...) return;`

### 5b. `build()`: dynamic body + dynamic nav items

Replace the hardcoded `tabs` list (161-170) with registry-driven bodies, and pass resolved `items` into all three renderers:

```dart
final defs = [for (final id in _visibleTabs) kTabRegistry[id]!];
final tabs = <Widget>[
  for (var i = 0; i < defs.length; i++)
    defs[i].builder(TabBuildContext(
      isActive: _index == i,
      shortsRefreshTick: _shortsRefreshTick,
    )),
];
```

- **PopScope** (184-189): `canPop: _index == _homeIndex`; on pop set `_index = _homeIndex` and `_navController.goTo(_homeIndex)`.
- **Desktop** `_SoplayFloatingNav(index: _index, onTap: _onTabTap, items: defs)`.
- **Mobile classic** `_SoplayClassicBar(..., items: defs)`.
- **Mobile glass/solid** `_SoplayGlassCapsule(..., items: defs)`.

`IndexedStack(index: _index, children: tabs)` is unchanged — body order == nav order == `_index` space, all three now come from the same `defs`, closing the "parallel lists must stay aligned" hazard.

### 5c. Make the three renderers take `items`, delete the static list

- **`_SoplayGlassCapsule`**: add `final List<AppTabDef> items;`; delete the `static const _items = [...]` (333-359); in `build()` iterate `items` (`for (final it in items) GlassTab(label: it.labelKey.tr(), icon: Icon(it.icon), activeIcon: Icon(it.activeIcon))`).
- **`_SoplayClassicBar`**: add `final List<AppTabDef> items;`; replace `_SoplayGlassCapsule._items` (483, 486) with `items`; replace shorts detection `i == _MainPageState._shortsIndex` (488, 492) with `items[i].id == TabId.shorts` (showcase key + double-tap now attach by identity, and simply don't attach if Shorts isn't visible).
- **`_SoplayFloatingNav`**: add `final List<AppTabDef> items;`; loop `for (int i = 0; i < items.length; i++) _NavCircle(item: items[i], ...)`.
- **`_ClassicNavButton` / `_NavCircle`**: change their `final _NavItem item;` field type to `final AppTabDef item;` — the fields `icon` / `activeIcon` / `labelKey` are identical, no body changes.
- **Delete** the private `_NavItem` class (735-745) — `AppTabDef` replaces it everywhere.

Desktop is otherwise untouched: same pill, same `AppColors.primary`/`navBackground`, now just fed a dynamic `items` list.

---

## 6. Customizer UI — NEW FILE `lib/features/profile/presentation/widgets/tab_customizer_sheet.dart`

Ports satashkent's `quick_nav_customizer.dart` (draft copy + atomic save + reorder + min/max), restyled to soplay tokens, count rule relaxed to 4–6, mandatory tabs locked.

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/nav_prefs.dart';
import 'package:soplay/core/theme/app_colors.dart';

Future<void> showTabCustomizer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.9,
      child: _TabCustomizerSheet(),
    ),
  );
}

class _TabCustomizerSheet extends StatefulWidget {
  const _TabCustomizerSheet();
  @override
  State<_TabCustomizerSheet> createState() => _TabCustomizerSheetState();
}

class _TabCustomizerSheetState extends State<_TabCustomizerSheet> {
  // Draft copy — nothing is persisted until Save.
  late List<TabId> _draft = sanitizeTabOrder(getIt<HiveService>().tabOrder);

  List<AppTabDef> get _available =>
      [for (final e in kTabRegistry.entries) if (!_draft.contains(e.key)) e.value];

  bool get _atMax => _draft.length >= kMaxTabs;
  bool get _atMin => _draft.length <= kMinTabs;
  bool get _valid => _draft.length >= kMinTabs && _draft.length <= kMaxTabs;

  void _snack(String key, {Map<String, String>? args}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(key.tr(namedArgs: args)), backgroundColor: AppColors.card),
      );

  void _pin(TabId id) {
    if (_atMax) return _snack('nav_customize.max_hint', args: {'count': '$kMaxTabs'});
    setState(() => _draft.add(id));
  }

  void _unpin(TabId id) {
    if (kTabRegistry[id]!.mandatory) return; // locked, no-op
    if (_atMin) return _snack('nav_customize.min_hint', args: {'count': '$kMinTabs'});
    setState(() => _draft.remove(id));
  }

  void _reorder(int oldI, int newI) => setState(() {
        if (newI > oldI) newI -= 1;
        _draft.insert(newI, _draft.removeAt(oldI));
      });

  Future<void> _save() async {
    if (!_valid) return _snack('nav_customize.pick_range',
        args: {'min': '$kMinTabs', 'max': '$kMaxTabs'});
    final encoded = encodeTabOrder(sanitizeTabOrder(encodeTabOrder(_draft)));
    await getIt<HiveService>().setTabOrder(encoded);
    NavPrefs.tabOrder.value = encoded; // shell listener rebuilds the bar live
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 10),
      Container(width: 40, height: 4,
        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Row(children: [
          Text('nav_customize.title'.tr(),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${_draft.length}/$kMaxTabs',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), children: [
          _label('nav_customize.shown'.tr()),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: _reorder,
            proxyDecorator: (child, i, anim) =>
                Material(color: Colors.transparent, elevation: 8, child: child),
            children: [
              for (var i = 0; i < _draft.length; i++)
                _PinnedTile(key: ValueKey(_draft[i].name), def: kTabRegistry[_draft[i]]!,
                    index: i, onRemove: () => _unpin(_draft[i])),
            ],
          ),
          if (_available.isNotEmpty) ...[
            const SizedBox(height: 8),
            _label('nav_customize.available'.tr()),
            for (final d in _available)
              _AvailableTile(def: d, disabled: _atMax, onAdd: () => _pin(d.id)),
          ],
        ]),
      ),
      _Footer(
        onReset: () => setState(() => _draft = List.of(kDefaultTabs)),
        onCancel: () => Navigator.pop(context),
        onSave: _save,
      ),
    ]);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: AppColors.textHint, fontSize: 11.5,
                fontWeight: FontWeight.w800, letterSpacing: 0.8)),
      );
}
```

`_PinnedTile` = a `Container` (bg `AppColors.background`, radius 14) with the tab's `activeIcon` in an `AppColors.primary@14%` circle, `labelKey.tr()`, then either a **lock icon** (`mandatory`) or a red `CupertinoIcons.minus_circle_fill` remove button, plus a trailing `ReorderableDragStartListener(index: index, child: Icon(Icons.drag_handle))`. `_AvailableTile` = same row with a brand `CupertinoIcons.plus_circle_fill` add button (dimmed when `disabled`). `_Footer` = a row of Reset / Cancel (ghost) / Save (filled `AppColors.primary`) buttons. All use `AppColors.primary` / `textPrimary` / `textSecondary` / `card` — matching `_navSegment`'s existing accent language.

*(The `_valid` guard is deliberately `min..max` — no even-count rule, because there's no center FAB. If a center action is ever added, re-introduce satashkent's even-split.)*

### Entry point — EDIT `profile_page.dart` `_AppearanceSection`

Inside the existing `if (isMobilePlatform) ...[` block (after the nav-style segment, ~line 2082), add a tile — same pattern as satashkent's settings `_NavTile`:

```dart
const Divider(height: 1, color: AppColors.divider),
ListTile(
  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
  leading: const Icon(Icons.dashboard_customize_rounded, color: AppColors.textSecondary),
  title: Text('nav_customize.entry_title'.tr(),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
  subtitle: Text('nav_customize.entry_subtitle'.tr(),
      style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
  trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
  onTap: () => showTabCustomizer(context),
),
```

Add `import '../widgets/tab_customizer_sheet.dart';` to `profile_page.dart`.

---

## 7. De-magic the 5 index call sites

| File:line | Now | Change to |
|---|---|---|
| `app.dart:111` | `getIt<NavController>().goTo(4);` | `getIt<NavController>().goToId(TabId.profile);` (Profile is mandatory → always resolves) |
| `streak_badge.dart:23,83` | `_profileTabIndex = 4` → `goTo(_profileTabIndex)` | delete const; `getIt<NavController>().goToId(TabId.profile);` |
| `home_top_bar.dart:71` | `getIt<NavController>().goTo(1)` | `final n = getIt<NavController>(); if (!n.goToId(TabId.search)) context.push('/search');` * |
| `home_content.dart:219` | `() => getIt<NavController>().goTo(3)` | `() { final n = getIt<NavController>(); if (!n.goToId(TabId.myList)) context.push('/my-list'); }` * |
| `my_list_page.dart:49,84` | `_tabIndex = 3` → `index.value != _tabIndex` | delete const; `if (!_navController.isActive(TabId.myList)) return;` |

Add `import 'package:soplay/core/navigation/app_tab.dart';` to each edited file.

\* **Fallback for removable targets:** Search and MyList are default-but-removable, so `goToId` can return false. The cheap, correct fallback is to push the feature's standalone route. If `/search` / `/my-list` routes don't already exist in `app_router.dart`, either (a) add them (the app_nav study notes several features already have standalone routes), or (b) make Search **mandatory** in the registry to sidestep the fallback entirely. Recommendation: keep Search mandatory (it's a primary action wired from the home top bar); leave MyList optional with a route fallback.

---

## 8. Translations — EDIT `assets/translations/{en,ru,uz}.json`

`navigation.downloads` already exists (en.json:290). Add the missing tab labels to the `navigation` block and a new `nav_customize` block:

```jsonc
"navigation": { ...,
  "history": "History", "following": "Following" },
"nav_customize": {
  "entry_title": "Customize tabs",
  "entry_subtitle": "Choose which tabs appear and their order",
  "title": "Bottom bar",
  "shown": "Shown", "available": "Available",
  "min_hint": "Keep at least {count} tabs",
  "max_hint": "Up to {count} tabs",
  "pick_range": "Pick between {min} and {max} tabs",
  "reset": "Reset", "cancel": "Cancel", "save": "Save"
}
```
(Provide ru/uz translations in the same shape.)

---

## 9. Step-by-step build order

1. **`app_tab.dart`** (registry, enum, constants, `sanitizeTabOrder`). Compiles standalone. `flutter analyze` — verify the 3 optional page imports resolve.
2. **`hive_service.dart`** — add `tabOrder` get/`setTabOrder`. Independent, compiles.
3. **`nav_prefs.dart`** — add `tabOrder` notifier. Independent.
4. **`nav_controller.dart`** — add `tabIndexResolver`, `goToId`, `isActive`. Compiles (imports app_tab).
5. **`main_page.dart`** — the big edit: import; `_visibleTabs` + getters; initState mirror+listener+resolver; dispose; `_onTabSetChange`; guard Shorts logic; registry-driven `tabs`/`defs`; PopScope by `_homeIndex`; thread `items:` into all 3 renderers; delete `_NavItem` + static `_items`; retype `_ClassicNavButton`/`_NavCircle` to `AppTabDef`. **Build & run — the bar should look identical (default 5 tabs).** This is the safe checkpoint before any UI.
6. **Translations** — add keys to en/ru/uz (so `.tr()` calls resolve before wiring UI).
7. **`tab_customizer_sheet.dart`** — new customizer.
8. **`profile_page.dart`** — add the entry tile + import. **Run: open sheet, reorder, add/remove, Save → bar updates live.**
9. **Call-site edits** (§7) one file at a time, `flutter analyze` after each. Add `/my-list` (and `/search` if not mandatory) routes if needed.
10. Full regression: switch nav styles (solid/glass/classic) with a customized set; desktop pill; keyboard-open hide; Shorts refresh showcase when Shorts is present *and* when it's removed; PopScope back-to-Home; streak/home deep jumps.

---

## 10. Migration / back-compat (flag)

- **Existing users have no `'tab_order'` key.** `HiveService.tabOrder` returns the literal `['home','search','shorts','myList','profile']`, and `NavPrefs.tabOrder`'s default is the same list → **the bar is byte-for-byte the current 5-tab layout on first launch after update. Zero visible change until the user opts in.** This is the migration contract; do not change these defaults.
- **`sanitizeTabOrder` runs on every read and write** (satashkent's `_sanitize` discipline): a value written by a newer build that references a `TabId` a rolled-back build doesn't know is silently dropped; a mandatory tab a user somehow lacks is force-added; counts are clamped to 4–6; anything degenerate falls back to `kDefaultTabs`. A corrupt Hive value can never empty or overflow the bar.
- **New optional tabs (downloads/history/following)** exist only in the registry + customizer; they are absent from `kDefaultTabs`, so they never appear unless a user adds them. Adding a brand-new feature tab later (Premiere, Kino Billar) = one `TabId` value + one registry entry + one `navigation.*` key — it auto-surfaces in the customizer's "Available" list and, if picked, in all three renderers, with **no shell edits**.
- **Removable-tab deep links** (§7 fallback): the only genuinely new failure mode is a `goToId` to a tab the user removed. Mitigated by keeping Search mandatory and giving MyList a route fallback; verify no other code path assumes a fixed index survives (the 5 sites in §7 are the complete set found by grep).

---

**Files to ADD (2):** `lib/core/navigation/app_tab.dart`, `lib/features/profile/presentation/widgets/tab_customizer_sheet.dart`.

**Files to EDIT (10):** `lib/core/storage/hive_service.dart`, `lib/core/system/nav_prefs.dart`, `lib/core/navigation/nav_controller.dart`, `lib/features/main/presentation/pages/main_page.dart`, `lib/features/profile/presentation/pages/profile_page.dart`, `lib/app.dart`, `lib/features/streak/presentation/widgets/streak_badge.dart`, `lib/features/home/presentation/widgets/home_top_bar.dart`, `lib/features/home/presentation/widgets/home_content.dart`, `lib/features/my_list/presentation/pages/my_list_page.dart`, plus `assets/translations/{en,ru,uz}.json`.

**No change to `app_router.dart`** for the tab set itself (tabs aren't routes) — only add `/my-list` (and optionally `/search`) routes if you want the removable-tab `goToId` fallbacks, or if a new tab should also be deep-linkable.