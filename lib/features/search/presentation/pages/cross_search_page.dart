import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:riasdxd/core/di/injection.dart';
import 'package:riasdxd/core/storage/hive_service.dart';
import 'package:riasdxd/core/theme/app_colors.dart';
import 'package:riasdxd/core/tv/tv.dart';
import 'package:riasdxd/features/detail/domain/entities/detail_args.dart';
import 'package:riasdxd/features/home/domain/entities/movie.dart';
import 'package:riasdxd/features/profile/domain/entities/provider_entity.dart';
import 'package:riasdxd/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:riasdxd/features/profile/presentation/bloc/provider_state.dart';
import 'package:riasdxd/features/search/domain/entities/cross_search_result.dart';
import 'package:riasdxd/features/search/domain/services/cross_search_engine.dart';
import 'package:riasdxd/features/search/presentation/blocs/cross_search_controller.dart';
import 'package:riasdxd/features/search/presentation/widgets/search_set_sheet.dart';

/// Search a curated set of providers at once. Results stream in, grouped by
/// provider — freeze-proof (bounded concurrency + per-provider timeout in the
/// engine), so a large or partly-broken set never blocks the UI.
class CrossSearchPage extends StatefulWidget {
  const CrossSearchPage({super.key, this.initialQuery});

  /// When set (e.g. opened from a title's "find on other sources"), the page
  /// starts searching for this immediately and does not steal focus.
  final String? initialQuery;

  @override
  State<CrossSearchPage> createState() => _CrossSearchPageState();
}

class _CrossSearchPageState extends State<CrossSearchPage> {
  final _textController = TextEditingController();
  late final CrossSearchController _controller;
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    final providers = _allProviders();
    _selectedIds = _initialSelection(providers);
    _controller = CrossSearchController(
      engine: getIt<CrossSearchEngine>(),
      set: _buildRefs(providers, _selectedIds),
    );
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _textController.text = q;
      _controller.onQueryChanged(q);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Offline this yields only the on-device plugins: fanning out to server
  /// providers with the API down would just add a row of failed legs.
  List<ProviderEntity> _allProviders() {
    final state = context.read<ProviderBloc>().state;
    return state is ProviderLoaded ? state.usableProviders : const [];
  }

  Set<String> _initialSelection(List<ProviderEntity> providers) {
    final hive = getIt<HiveService>();
    final existing = providers.map((p) => p.id).toSet();
    var ids = hive.getCrossSearchProviders().where(existing.contains).toSet();
    if (ids.isEmpty) {
      ids = hive.getFavoriteProviders().where(existing.contains).toSet();
    }
    if (ids.isEmpty) {
      final current = hive.getCurrentProvider();
      if (current.isNotEmpty && existing.contains(current)) ids = {current};
    }
    return ids;
  }

  List<ProviderRef> _buildRefs(List<ProviderEntity> providers, Set<String> ids) {
    return providers
        .where((p) => ids.contains(p.id))
        .map(ProviderRef.fromEntity)
        .toList();
  }

  Future<void> _openSetSheet() async {
    final providers = _allProviders();
    final result = await SearchSetSheet.show(
      context,
      providers: providers,
      initialSelected: _selectedIds,
    );
    if (result == null || !mounted) return;
    _selectedIds = result;
    await getIt<HiveService>().setCrossSearchProviders(result.toList());
    _controller.setProviderSet(_buildRefs(providers, result));
    setState(() {});
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
        title: const Text('All-source search',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchField(),
          _sourcesBar(),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _textController,
        autofocus: (widget.initialQuery ?? '').trim().isEmpty,
        style: const TextStyle(color: Colors.white),
        textInputAction: TextInputAction.search,
        onChanged: _controller.onQueryChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search across your sources…',
          hintStyle: const TextStyle(color: AppColors.textHint),
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textHint, size: 20),
          suffixIcon: _textController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textHint),
                  onPressed: () {
                    _textController.clear();
                    _controller.onQueryChanged('');
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _sourcesBar() {
    final label = _selectedIds.isEmpty
        ? 'No sources selected — tap to choose'
        : '${_selectedIds.length} source(s) selected — tap to change';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _openSetSheet,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 16, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_selectedIds.isEmpty) {
      return _centered(
        icon: Icons.tune,
        text: 'Pick which sources to search across.',
        action: FilledButton(
          onPressed: _openSetSheet,
          child: const Text('Choose sources'),
        ),
      );
    }
    if (_controller.query.isEmpty) {
      return _centered(
        icon: Icons.travel_explore,
        text: 'Type to search all ${_selectedIds.length} selected sources '
            'at once.',
      );
    }

    final results = _controller.results;
    final withItems = results.where((r) => r.hasItems).toList();
    final withoutItems = results.where((r) => !r.hasItems).toList();
    final pending = _controller.expectedLegs - _controller.completedLegs;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _summary(pending),
        for (final r in withItems) _providerSection(r),
        if (withoutItems.isNotEmpty) _noResultFooter(withoutItems),
        if (withItems.isEmpty && pending <= 0)
          _centered(
            icon: Icons.search_off,
            text: 'No results in any selected source.',
            padded: false,
          ),
      ],
    );
  }

  Widget _summary(int pending) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          if (_controller.searching && pending > 0) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              'Found in ${_controller.sourcesWithResults} of '
              '${_controller.expectedLegs} sources · '
              '${_controller.totalItems} results'
              '${pending > 0 ? ' · searching…' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerSection(ProviderSearchResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  r.provider.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${r.items.length}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 188,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: r.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final m = r.items[i];
              // Open the detail with the SOURCE this result came from — not the
              // app's "current" provider. Server legs are collapsed under the
              // synthetic __server__ ref, so use the item's own backend provider
              // there; channel/js legs carry the real id on the section ref.
              final prov = r.provider.kind == ProviderKind.server
                  ? (m.provider.isNotEmpty ? m.provider : null)
                  : r.provider.id;
              return _MovieCard(
                movie: m,
                alsoOn: _controller.crossSourceCount(m.title, m.year),
                provider: prov,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _noResultFooter(List<ProviderSearchResult> list) {
    final noResults = list.where((r) => r.status == ProviderSearchStatus.empty).length;
    final timeouts = list.where((r) => r.status == ProviderSearchStatus.timeout).length;
    final errors = list.where((r) => r.status == ProviderSearchStatus.error).length;
    final parts = <String>[
      if (noResults > 0) '$noResults with no results',
      if (timeouts > 0) '$timeouts timed out',
      if (errors > 0) '$errors failed',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(parts.join(' · '),
          style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
    );
  }

  Widget _centered({
    required IconData icon,
    required String text,
    Widget? action,
    bool padded = true,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textHint.withValues(alpha: 0.5), size: 56),
        const SizedBox(height: 14),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textHint, fontSize: 14)),
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    );
    if (!padded) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 60), child: Center(child: content));
    }
    return Center(
      child: Padding(padding: const EdgeInsets.all(32), child: content),
    );
  }
}

class _MovieCard extends StatelessWidget {
  const _MovieCard({required this.movie, required this.alsoOn, this.provider});

  final MovieEntity movie;
  final int alsoOn;
  final String? provider;

  @override
  Widget build(BuildContext context) {
    // Android TV: these cards are every result of a cross-provider search, so a
    // bare GestureDetector made the whole results grid unreachable by the D-pad.
    // Off TV TvFocusable collapses to exactly the GestureDetector that was here
    // — same onTap, same explicit HitTestBehavior.opaque, nothing else added.
    return TvFocusable(
      behavior: HitTestBehavior.opaque,
      onPressed: () {
        if (movie.url.isEmpty) return;
        context.push('/detail',
            extra: DetailArgs(
                contentUrl: movie.url, preview: movie, provider: provider));
      },
      child: SizedBox(
        width: 116,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  SizedBox(
                    width: 116,
                    height: 150,
                    child: movie.thumbnail != null
                        ? Image.network(
                            movie.thumbnail!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                  if (alsoOn > 1)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$alsoOn sources',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11.5, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.movie_rounded,
            color: AppColors.textHint, size: 30),
      );
}
