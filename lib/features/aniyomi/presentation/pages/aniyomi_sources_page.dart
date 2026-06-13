import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';

class AniyomiSourcesPage extends StatefulWidget {
  const AniyomiSourcesPage({super.key});

  @override
  State<AniyomiSourcesPage> createState() => _AniyomiSourcesPageState();
}

class _AniyomiSourcesPageState extends State<AniyomiSourcesPage> {
  static const List<Map<String, String>> _recommended = [
    {
      'name': 'Yuzono Anime',
      'desc': 'Largest collection · 270+ sources',
      'url':
          'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json',
    },
    {
      'name': 'Secozzi',
      'desc': 'Jellyfin · Stremio · Torbox',
      'url':
          'https://raw.githubusercontent.com/Secozzi/aniyomi-extensions/repo/index.min.json',
    },
  ];

  final _controller = TextEditingController();
  List<Map<String, String>> _repos = const [];
  bool _busy = false;
  bool _nsfw = false;
  String? _status;
  bool _statusError = false;
  StreamSubscription<({int current, int total})>? _progressSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadNsfw();
    _progressSub = AniyomiChannel.installProgress.listen((p) {
      if (!mounted || !_busy) return;
      setState(() {
        _status = p.total > 0
            ? 'Installing ${p.current} / ${p.total} extensions…'
            : 'Installing extensions…';
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

  Future<void> _loadNsfw() async {
    final v = await AniyomiChannel.isNsfwEnabled();
    if (!mounted) return;
    setState(() => _nsfw = v);
  }

  Future<void> _toggleNsfw(bool v) async {
    setState(() => _nsfw = v);
    await AniyomiChannel.setNsfwEnabled(v);
    _reloadProviders();
  }

  Future<void> _refresh() async {
    final repos = await AniyomiChannel.listRepos();
    if (!mounted) return;
    setState(() => _repos = repos.map((e) {
          final m = (e is Map) ? e : const {};
          final url = (m['url'] ?? e).toString();
          final name = (m['name'] ?? '').toString();
          return {'url': url, 'name': name.isNotEmpty ? name : url};
        }).toList());
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
      _status = 'Installing extensions… this can take a moment for large repos.';
    });
    try {
      final res = await AniyomiChannel.addRepo(input);
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
            ? 'No extensions found at that URL.'
            : 'Added $count source(s) · $providers provider(s).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String url) async {
    await AniyomiChannel.removeRepo(url);
    if (!mounted) return;
    _reloadProviders();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _statusError = false;
      _status = 'Source removed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AniyomiChannel.isSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Aniyomi Sources')),
        body: const Center(
          child: Text('This feature is only available on Android'),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Aniyomi Sources'),
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
          const SizedBox(height: 20),
          _nsfwCard(),
          const SizedBox(height: 24),
          _recommendedSection(),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('INSTALLED SOURCES',
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
        ],
      ),
    );
  }

  Widget _header() => Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.play_circle_outline,
                color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add Aniyomi extension repositories to install extra anime '
              'providers. They run on your device (Android only).',
              style: TextStyle(
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
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Repo URL',
                hintText: 'https://…/index.min.json',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
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
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add),
                label: Text(_busy ? 'Installing…' : 'Add source'),
              ),
            ),
          ],
        ),
      );

  Widget _nsfwCard() => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SwitchListTile(
          value: _nsfw,
          onChanged: _busy ? null : _toggleNsfw,
          activeThumbColor: AppColors.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          title: const Text('Show 18+ sources',
              style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text('Include NSFW extensions in the provider list',
              style: TextStyle(color: AppColors.textHint, fontSize: 11.5)),
          secondary: const Icon(Icons.explicit_outlined, color: AppColors.textHint),
        ),
      );

  bool _isInstalled(String url) =>
      _repos.any((r) => (r['url'] ?? '').trim() == url.trim());

  Widget _recommendedSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('RECOMMENDED',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textHint, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Not sure what to paste? Tap one to install it.',
              style: TextStyle(color: AppColors.textHint, fontSize: 11.5),
            ),
          ),
          ..._recommended.map(_recommendedTile),
        ],
      );

  Widget _recommendedTile(Map<String, String> repo) {
    final url = repo['url'] ?? '';
    final name = repo['name'] ?? url;
    final desc = repo['desc'] ?? '';
    final installed = _isInstalled(url);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: installed
              ? Colors.green.withValues(alpha: 0.35)
              : AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: ListTile(
        onTap: (_busy || installed) ? null : () => _install(url),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.play_circle_outline,
              color: AppColors.primary, size: 22),
        ),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(desc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11.5)),
        trailing: installed
            ? const _InstalledChip()
            : Icon(Icons.download_rounded,
                color: _busy ? AppColors.textHint : AppColors.primary),
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
        child: const Column(
          children: [
            Icon(Icons.cloud_off_outlined, color: AppColors.textHint, size: 32),
            SizedBox(height: 8),
            Text('No sources yet', style: TextStyle(color: AppColors.textHint)),
          ],
        ),
      );

  Widget _repoTile(Map<String, String> repo) {
    final url = repo['url'] ?? '';
    final name = repo['name'] ?? url;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.play_circle_outline,
              color: AppColors.primary, size: 20),
        ),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: _busy ? null : () => _remove(url),
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green),
            SizedBox(width: 4),
            Text('Installed',
                style: TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
