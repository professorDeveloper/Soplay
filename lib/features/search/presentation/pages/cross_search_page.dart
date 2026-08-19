import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';
import 'package:soplay/features/search/presentation/blocs/cross_search_controller.dart';
import 'package:soplay/features/search/presentation/widgets/search_result_card.dart';
import 'package:soplay/features/search/presentation/widgets/search_set_sheet.dart';
class CrossSearchPage extends StatefulWidget {
  const CrossSearchPage({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  State<CrossSearchPage> createState() => _CrossSearchPageState();
}

class _CrossSearchPageState extends State<CrossSearchPage> {
  final _textController = TextEditingController();
  late final CrossSearchController _controller;

  Set<String> _selectedIds = {};
  List<ProviderEntity> _providers = const [];
  bool _offline = false;
  bool _grouped = false;

  @override
  void initState() {
    super.initState();
    _providers = _providersOf(context.read<ProviderBloc>().state);
    _selectedIds = _initialSelection(_providers);
    _controller = CrossSearchController(
      engine: getIt<CrossSearchEngine>(),
      set: _buildRefs(_providers, _selectedIds),
    );
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _textController.text = q;
      _controller.submit(q);
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
  List<ProviderEntity> _providersOf(ProviderState state) =>
      state is ProviderLoaded ? state.usableProviders : const [];

  /// The page used to snapshot ProviderBloc once in initState, so opening it
  /// before the providers had loaded left it permanently empty.
  void _syncProviders(ProviderState state) {
    final providers = _providersOf(state);
    final offline = state is ProviderLoaded && state.offline;
    if (providers.length == _providers.length &&
        offline == _offline &&
        providers.every((p) => _providers.any((e) => e.id == p.id))) {
      return;
    }
    final wasEmpty = _providers.isEmpty;
    _providers = providers;
    _offline = offline;
    if (wasEmpty || _selectedIds.isEmpty) {
      _selectedIds = _initialSelection(providers);
    } else {
      _selectedIds = _selectedIds
          .where((id) => providers.any((p) => p.id == id))
          .toSet();
    }
    setState(() {});
    _controller.setProviderSet(_buildRefs(providers, _selectedIds));
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
    final result = await SearchSetSheet.show(
      context,
      providers: _providers,
      initialSelected: _selectedIds,
    );
    if (result == null || !mounted) return;
    _selectedIds = result;
    await getIt<HiveService>().setCrossSearchProviders(result.toList());
    _controller.setProviderSet(_buildRefs(_providers, result));
    setState(() {});
  }

  void _openDetail(MergedSearchTitle title) {
    if (title.sourceCount <= 1) {
      _push(title.hits.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                'search.open_from'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final hit in title.hits)
              ListTile(
                dense: true,
                leading: const Icon(Icons.play_circle_outline,
                    color: AppColors.primary, size: 20),
                title: Text(hit.provider.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(hit.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 12)),
                onTap: () {
                  Navigator.of(context).pop();
                  _push(hit);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _push(TitleHit hit) {
    if (hit.item.url.isEmpty) return;
    context.push(
      '/detail',
      extra: DetailArgs(
        contentUrl: hit.item.url,
        preview: hit.item,
        provider: _providerIdOf(hit),
      ),
    );
  }

  /// The source this hit came from, never the app's "current" provider.
  String? _providerIdOf(TitleHit hit) {
    if (hit.provider.kind == ProviderKind.server &&
        hit.item.provider.isNotEmpty) {
      return hit.item.provider;
    }
    return hit.provider.id;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProviderBloc, ProviderState>(
      listener: (_, state) => _syncProviders(state),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          title: Text('search.all_source_search'.tr(),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: _grouped
                  ? 'search.merge_titles'.tr()
                  : 'search.group_by_source'.tr(),
              onPressed: () => setState(() => _grouped = !_grouped),
              icon: Icon(
                _grouped ? Icons.grid_view_rounded : Icons.view_agenda_outlined,
                size: 20,
              ),
            ),
          ],
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
        onSubmitted: (value) {
          FocusScope.of(context).unfocus();
          _controller.submit(value);
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: 'search.cross_hint'.tr(),
          hintStyle: const TextStyle(color: AppColors.textHint),
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textHint, size: 20),
          // Driven by the controller: nothing else subscribes to it, so the
          // clear button used to appear only on an unrelated rebuild.
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textController,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textHint),
                    onPressed: () {
                      _textController.clear();
                      _controller.onQueryChanged('');
                    },
                  ),
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
        ? 'search.no_sources_selected'.tr()
        : 'search.sources_selected'.tr(args: ['${_selectedIds.length}']);
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
        text: 'search.pick_sources'.tr(),
        action: FilledButton(
          onPressed: _openSetSheet,
          child: Text('search.choose_sources'.tr()),
        ),
      );
    }
    if (_controller.query.isEmpty) {
      return _centered(
        icon: Icons.travel_explore,
        text: 'search.type_to_search_n'
            .tr(args: ['${_controller.expectedLegs}']),
      );
    }

    final merged = _controller.merged;
    final done = _controller.phase == CrossSearchPhase.done;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: _summary()),
        if (_offline)
          SliverToBoxAdapter(child: _note('search.offline_note'.tr())),
        if (merged.isEmpty && done)
          SliverToBoxAdapter(
            child: _centered(
              icon: Icons.search_off,
              text: 'search.no_results_any'.tr(),
              padded: false,
            ),
          )
        else if (_grouped)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _providerSection(_controller.legsWithItems[i]),
              childCount: _controller.legsWithItems.length,
            ),
          )
        else
          _mergedGrid(merged),
        if (_controller.hasMoreAnywhere && done)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: OutlinedButton(
                  onPressed:
                      _controller.loadingMore ? null : _controller.loadMore,
                  child: _controller.loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('search.load_more'.tr()),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: _sourceStatusList()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _mergedGrid(List<MergedSearchTitle> merged) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final title = merged[i];
            return SearchResultCard(
              key: ValueKey('${title.key}|${title.year ?? ''}'),
              movie: title.primary,
              provider: _providerIdOf(title.hits.first),
              sourceLabel: title.sourceCount > 1
                  ? 'search.sources_n'.tr(args: ['${title.sourceCount}'])
                  : title.primaryProvider.name,
              sourceCount: title.sourceCount,
              onTap: () => _openDetail(title),
            );
          },
          childCount: merged.length,
        ),
        gridDelegate: searchGridDelegate(context),
      ),
    );
  }

  Widget _summary() {
    final pending = _controller.pendingSources;
    final searching = _controller.searching;
    final text = searching
        ? (pending.isEmpty
            ? 'search.searching'.tr()
            : 'search.waiting_for'.tr(args: [pending.take(2).join(', ')]))
        : 'search.found_in'.tr(args: [
            '${_controller.sourcesWithResults}',
            '${_controller.expectedLegs}',
          ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          if (searching) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              '$text · ${'search.results_n'.tr(args: ['${_controller.totalItems}'])}',
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
      key: ValueKey('section-${r.provider.id}'),
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
          height: searchCardHeight(116),
          child: ListView.separated(
            key: PageStorageKey('cross-rail-${r.provider.id}'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: r.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final m = r.items[i];
              final hit = TitleHit(provider: r.provider, item: m);
              return SearchResultCard(
                width: 116,
                movie: m,
                provider: _providerIdOf(hit),
                sourceLabel: m.year != null ? '${m.year}' : '',
                onTap: () => _push(hit),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Every leg by name with what it did, and a Retry for the ones that failed.
  Widget _sourceStatusList() {
    final legs = _controller.results;
    if (legs.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _controller.failedLegs.isNotEmpty,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          'search.sources'.tr(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        children: [
          for (final leg in legs)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 16, right: 8),
              title: Text(leg.provider.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text(
                _statusLabel(leg),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textHint, fontSize: 11.5),
              ),
              trailing: leg.status == ProviderSearchStatus.ok
                  ? null
                  : _controller.isRetrying(leg.provider.id)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () =>
                              _controller.retryProvider(leg.provider.id),
                          child: Text('general.retry'.tr()),
                        ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(ProviderSearchResult leg) => switch (leg.status) {
        ProviderSearchStatus.ok =>
          'search.results_n'.tr(args: ['${leg.items.length}']),
        ProviderSearchStatus.empty => 'search.no_results'.tr(),
        ProviderSearchStatus.timeout => 'errors.timeout'.tr(),
        ProviderSearchStatus.error => leg.message.isEmpty
            ? 'search.source_failed'.tr()
            : leg.message,
      };

  Widget _note(String text) => Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.orange, fontSize: 11.5, height: 1.3)),
      );

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
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Center(child: content));
    }
    return Center(
      child: Padding(padding: const EdgeInsets.all(32), child: content),
    );
  }
}
