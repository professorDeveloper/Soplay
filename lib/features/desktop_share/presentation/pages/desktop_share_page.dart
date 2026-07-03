import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/extensions/extension_bridge.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// Share the phone's CloudStream / Aniyomi / Manga sources with the Sozo desktop
/// app over the same Wi‑Fi. On **Android** this is the host (a toggle + a link);
/// on **desktop / iOS** it's the client (paste the phone's link).
class DesktopSharePage extends StatefulWidget {
  const DesktopSharePage({super.key});

  @override
  State<DesktopSharePage> createState() => _DesktopSharePageState();
}

class _DesktopSharePageState extends State<DesktopSharePage> {
  BridgeStatus _status = const BridgeStatus(enabled: false, link: null);
  bool _busy = false;
  final TextEditingController _urlCtrl = TextEditingController();

  bool get _isHost => BridgeControl.canHost;

  @override
  void initState() {
    super.initState();
    if (_isHost) {
      _refresh();
    } else {
      _urlCtrl.text = getIt<HiveService>().getBridgeUrl();
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await BridgeControl.getStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final s = await BridgeControl.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _status = s;
      _busy = false;
    });
  }

  Future<void> _saveUrl() async {
    final url = _urlCtrl.text.trim();
    await getIt<HiveService>().setBridgeUrl(url);
    ExtensionBridge.setUrl(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          url.isEmpty
              ? 'Desktop sources turned off.'
              : 'Saved. Reopen Home / Search to load the sources.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(_isHost ? 'Share sources to desktop' : 'Desktop sources'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: _isHost ? _hostBody() : _clientBody(),
        ),
      ),
    );
  }

  // ---- Android (host) ------------------------------------------------------

  List<Widget> _hostBody() {
    final link = _status.link;
    return [
      _card(
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Share sources with desktop',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch.adaptive(
                value: _status.enabled,
                activeThumbColor: AppColors.primary,
                onChanged: _toggle,
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (_status.enabled && link != null)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your link',
                style: TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      link,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    color: AppColors.primary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        )
      else if (_status.enabled)
        _card(
          child: const Text(
            "Turned on, but no Wi‑Fi address was found. Connect this phone to "
            "Wi‑Fi (not mobile data), then reopen this screen.",
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      const SizedBox(height: 16),
      _instructions(const [
        'Keep this phone and your PC on the same Wi‑Fi network.',
        'Turn on the switch above.',
        'On the PC, open Sozo → Profile → Desktop sources and paste the link.',
        'Keep Sozo open on this phone while you browse on the PC.',
      ]),
    ];
  }

  // ---- Desktop / iOS (client) ----------------------------------------------

  List<Widget> _clientBody() {
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Phone link',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'http://192.168.x.x:8765',
                hintStyle: TextStyle(color: AppColors.textHint),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _saveUrl,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _instructions(const [
        'Keep this PC and your phone on the same Wi‑Fi network.',
        'On the phone, open Sozo → Profile → Share sources to desktop and turn it on.',
        'Copy the link shown there, paste it above, then tap Save.',
        'Keep Sozo open on the phone while you browse here.',
      ]),
    ];
  }

  // ---- shared --------------------------------------------------------------

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );

  Widget _instructions(List<String> steps) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How it works',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Use your CloudStream, Aniyomi & manga sources on the Sozo desktop '
              'app. The phone runs the sources; the PC just views them.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
