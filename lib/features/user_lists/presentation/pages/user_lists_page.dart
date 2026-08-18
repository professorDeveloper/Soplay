import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';
import 'package:soplay/features/user_lists/domain/repositories/user_lists_repository.dart';

/// The user's curated lists, one tab per [UserListKind].
///
/// A page of its own rather than another mode inside `MyListPage`: that page is
/// driven by `MyListBloc` around a single favorites source, and threading two
/// more sources through it would couple three independent lists to one bloc.
/// Tabs are generated from the enum, so a third list needs no code here.
class UserListsPage extends StatefulWidget {
  const UserListsPage({super.key, this.initialKind});

  /// Which tab opens first — used when arriving from a "Watch Later" shortcut.
  final UserListKind? initialKind;

  @override
  State<UserListsPage> createState() => _UserListsPageState();
}

class _UserListsPageState extends State<UserListsPage>
    with SingleTickerProviderStateMixin {
  static const _kinds = UserListKind.values;

  late final TabController _tabs = TabController(
    length: _kinds.length,
    vsync: this,
    initialIndex: widget.initialKind == null
        ? 0
        : _kinds.indexOf(widget.initialKind!).clamp(0, _kinds.length - 1),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 16,
        title: const Text(
          'My Lists',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        bottom: AppTabBar(
          // Two tabs: split the bar rather than hugging the left edge.
          isScrollable: false,
          controller: _tabs,
          labels: [for (final k in _kinds) k.label],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [for (final k in _kinds) _UserListTab(kind: k)],
      ),
    );
  }
}

class _UserListTab extends StatefulWidget {
  const _UserListTab({required this.kind});

  final UserListKind kind;

  @override
  State<_UserListTab> createState() => _UserListTabState();
}

class _UserListTabState extends State<_UserListTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<FavoriteEntity>> _future = _load();

  @override
  bool get wantKeepAlive => true;

  Future<List<FavoriteEntity>> _load() async {
    final result = await getIt<UserListsRepository>().getList(widget.kind);
    return result.getOrNull() ?? const [];
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _remove(FavoriteEntity item) async {
    await getIt<UserListsRepository>().remove(widget.kind, item.contentUrl);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<FavoriteEntity>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? const <FavoriteEntity>[];
        if (items.isEmpty) {
          // The repository never surfaces an error — a failed fetch falls back
          // to the cache — so "empty" is the only empty-ish state there is.
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    'Nothing in ${widget.kind.label} yet',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = items[i];
              return ListTile(
                leading: item.thumbnail.isEmpty
                    ? const SizedBox(width: 44)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          item.thumbnail,
                          width: 44,
                          height: 62,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(width: 44),
                        ),
                      ),
                title: Text(
                  item.title.isEmpty ? item.contentUrl : item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  item.provider,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => _remove(item),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
