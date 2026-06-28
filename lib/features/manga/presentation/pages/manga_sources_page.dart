import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/manga/presentation/pages/manga_source_settings_page.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';

class MangaSourcesPage extends StatefulWidget {
  const MangaSourcesPage({super.key});

  @override
  State<MangaSourcesPage> createState() => _MangaSourcesPageState();
}

class _MangaSourcesPageState extends State<MangaSourcesPage> {
  static const String _logo =
      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s';
  static const Color _accent = Color(0xFF5B8DEF);

  static const List<Map<String, String>> _recommended = [
    {
      'name': 'Yuzono Manga',
      'desc': 'Largest collection · auto-synced with Keiyoushi',
      'url':
          'https://raw.githubusercontent.com/yuzono/manga-repo/repo/index.min.json',
    },
    {
      'name': 'Keiyoushi',
      'desc': 'Community manga / manhwa / webtoon sources',
      'url':
          'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
    },
  ];

  final _controller = TextEditingController();
  List<Map<String, String>> _repos = const [];
  List<Map<String, dynamic>> _sources = const [];
  bool _busy = false;
  bool _recommendedHidden = false;
  String? _status;
  bool _statusError = false;
  StreamSubscription<({int current, int total})>? _progressSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _progressSub = MangaChannel.installProgress.listen((p) {
      if (!mounted || !_busy) return;
      setState(() {
        _status = p.total > 0
            ? 'manga.installing_progress'
                .tr(args: ['${p.current}', '${p.total}'])
            : 'manga.installing'.tr();
        _statusError = false;
      });
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repos = await MangaChannel.listRepos();
    final sources = await MangaChannel.listProviders();
    if (!mounted) return;
    setState(() {
      _repos = repos.map((e) {
        final m = (e is Map) ? e : const {};
        final url = (m['url'] ?? e).toString();
        final name = (m['name'] ?? '').toString();
        return {'url': url, 'name': name.isNotEmpty ? name : url};
      }).toList();
      _sources = sources
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  }

  void _openSourceSettings(Map<String, dynamic> source) {
    final id = (source['id'] as String? ?? '');
    final bareId = id.startsWith('mn:') ? id.substring(3) : id;
    final name = (source['name'] as String?) ?? bareId;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MangaSourceSettingsPage(sourceId: bareId, name: name),
      ),
    );
  }

  void _reloadProviders() {
    try {
      context.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
  }

  Future<void> _add() => _install(_controller.text.trim());

  Future<void> _install(String input) async {
    if (input.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _statusError = false;
      _status = 'manga.installing_long'.tr();
    });
    try {
      final res = await MangaChannel.addRepo(input);
      final count = res['sourceCount'] ?? 0;
      final providers = (res['providers'] as List?)?.length ?? 0;
      if (!mounted) return;
      if (count > 0) {
        _controller.clear();
        _reloadProviders();
      }
      await _refresh();
      if (!mounted) return;
      setState(() {
        _statusError = count == 0;
        _status = count == 0
            ? 'manga.no_extensions'.tr()
            : 'manga.added_sources'.tr(args: ['$count', '$providers']);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = 'manga.error_prefix'.tr(args: ['$e']);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String url) async {
    await MangaChannel.removeRepo(url);
    if (!mounted) return;
    _reloadProviders();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _statusError = false;
      _status = 'manga.source_removed'.tr();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!MangaChannel.isSupported) {
      return Scaffold(
        appBar: AppBar(title: Text('manga.sources_title'.tr())),
        body: Center(
          child: Text('manga.android_only'.tr()),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('manga.sources_title'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _header(),
          const SizedBox(height: 16),
          _addCard(),
          if (_status != null) ...[
            const SizedBox(height: 12),
            _statusBanner(),
          ],
          const SizedBox(height: 24),
          _recommendedSection(),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('manga.installed_sources'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textHint, letterSpacing: 1)),
              const Spacer(),
              if (_repos.isNotEmpty)
                Text('${_repos.length}',
                    style: const TextStyle(color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          if (_repos.isEmpty) _empty() else ..._repos.map(_repoTile),
          if (_sources.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.tune, size: 15, color: _accent),
                const SizedBox(width: 6),
                Text('manga.source_settings'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textHint, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 8),
            ..._sources.map(_sourceTile),
          ],
        ],
      ),
    );
  }

  Widget _sourceTile(Map<String, dynamic> source) {
    final name = (source['name'] as String?) ?? '';
    final lang = (source['lang'] as String?) ?? '';
    final nsfw = source['nsfw'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: _logoBox(34),
          title: Row(
            children: [
              Flexible(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              if (nsfw) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('18+',
                      style: TextStyle(
                          color: Color(0xFFE53935),
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          subtitle: lang.isNotEmpty
              ? Text(lang.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.textHint, fontSize: 11))
              : null,
          trailing: const Icon(Icons.settings_outlined,
              color: AppColors.textHint),
          onTap: () => _openSourceSettings(source),
        ),
      ),
    );
  }

  Widget _logoBox(double size, {double radius = 9}) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          _logo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: Colors.white10,
            child: Icon(Icons.menu_book_outlined,
                color: Colors.white54, size: size * 0.55),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          _logoBox(44, radius: 11),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'manga.sources_desc'.tr(),
              style: const TextStyle(
                  color: AppColors.textHint, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      );

  Widget _addCard() => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              enabled: !_busy,
              cursorColor: _accent,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'manga.repo_url'.tr(),
                labelStyle: const TextStyle(color: AppColors.textHint),
                floatingLabelStyle: const TextStyle(color: _accent),
                hintText: 'https://…/index.min.json',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: _accent.withValues(alpha: 0.6), width: 1.4),
                ),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textHint),
                        tooltip: 'Clear',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _controller.clear()),
                      ),
              ),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add),
                label: Text(_busy ? 'manga.installing'.tr() : 'manga.add_source'.tr()),
              ),
            ),
          ],
        ),
      );

  bool _isInstalled(String url) =>
      _repos.any((r) => (r['url'] ?? '').trim() == url.trim());

  Widget _recommendedSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 15, color: _accent),
              const SizedBox(width: 6),
              Text('manga.recommended'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textHint, letterSpacing: 1)),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(
                    () => _recommendedHidden = !_recommendedHidden),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                      _recommendedHidden
                          ? 'manga.show'.tr()
                          : 'manga.hide'.tr(),
                      style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          if (!_recommendedHidden) ...[
            const SizedBox(height: 8),
            ..._recommended.map(_recommendedTile),
          ],
        ],
      );

  Widget _recommendedTile(Map<String, String> repo) {
    final url = repo['url'] ?? '';
    final name = repo['name'] ?? url;
    final desc = repo['desc'] ?? '';
    final installed = _isInstalled(url);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: (_busy || installed) ? null : () => _install(url),
          splashColor: _accent.withValues(alpha: 0.12),
          highlightColor: _accent.withValues(alpha: 0.06),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: installed
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _logoBox(30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textHint, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                installed
                    ? const _InstalledChip()
                    : Icon(Icons.download_rounded,
                        size: 20,
                        color: _busy ? AppColors.textHint : _accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBanner() {
    final color = _statusError ? Colors.redAccent : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (_busy)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(_statusError ? Icons.error_outline : Icons.check_circle_outline,
                size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(_status!, style: TextStyle(color: color, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppColors.textHint, size: 32),
            const SizedBox(height: 8),
            Text('manga.no_sources'.tr(),
                style: const TextStyle(color: AppColors.textHint)),
          ],
        ),
      );

  Widget _repoTile(Map<String, String> repo) {
    final url = repo['url'] ?? '';
    final name = repo['name'] ?? url;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: _logoBox(34),
          title: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _busy ? null : () => _remove(url),
          ),
        ),
      ),
    );
  }
}

class _InstalledChip extends StatelessWidget {
  const _InstalledChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Text('manga.installed'.tr(),
                style: const TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
