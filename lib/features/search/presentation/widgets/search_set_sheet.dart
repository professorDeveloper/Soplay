import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';

/// Multi-select for the cross-search provider set. Returns the chosen ids via
/// `Navigator.pop(context, Set<String>)`, or `null` if dismissed.
///
/// Kept deliberately explicit: with 200+ installed providers, searching all
/// would be slow, so the user curates a small set here.
class SearchSetSheet extends StatefulWidget {
  const SearchSetSheet({
    super.key,
    required this.providers,
    required this.initialSelected,
  });

  final List<ProviderEntity> providers;
  final Set<String> initialSelected;

  static Future<Set<String>?> show(
    BuildContext context, {
    required List<ProviderEntity> providers,
    required Set<String> initialSelected,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SearchSetSheet(
        providers: providers,
        initialSelected: initialSelected,
      ),
    );
  }

  @override
  State<SearchSetSheet> createState() => _SearchSetSheetState();
}

class _SearchSetSheetState extends State<SearchSetSheet> {
  late final Set<String> _selected = {...widget.initialSelected};
  String _query = '';

  static const int _softCap = 15;

  List<ProviderEntity> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.providers;
    return widget.providers
        .where((p) =>
            p.name.toLowerCase().contains(q) || p.id.toLowerCase().contains(q))
        .toList();
  }

  String _tag(ProviderEntity p) {
    if (p.id.startsWith('cs:')) return 'CS';
    if (p.id.startsWith('an:')) return 'AN';
    if (p.id.startsWith('mn:')) return 'MN';
    return p.scopesAll ? 'JS' : 'SOZO';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final items = _filtered;
    final overCap = _selected.length > _softCap;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Search sources',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                          Text('${_selected.length} selected',
                              style: const TextStyle(
                                  color: AppColors.textHint, fontSize: 12)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => setState(_selected.clear),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Filter providers…',
                    hintStyle: const TextStyle(color: AppColors.textHint),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textHint, size: 20),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (overCap)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Searching ${_selected.length} sources may be slow. '
                    'The app stays responsive, but fewer is snappier.',
                    style: const TextStyle(
                        color: Colors.orange, fontSize: 11.5, height: 1.3),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final p = items[i];
                    final on = _selected.contains(p.id);
                    return CheckboxListTile(
                      value: on,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      onChanged: (_) => setState(() {
                        if (on) {
                          _selected.remove(p.id);
                        } else {
                          _selected.add(p.id);
                        }
                      }),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(_tag(p),
                                style: const TextStyle(
                                    color: AppColors.textHint,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: Text('Apply (${_selected.length})'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
