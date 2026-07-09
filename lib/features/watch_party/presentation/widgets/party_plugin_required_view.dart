import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/features/aniyomi/presentation/pages/aniyomi_sources_page.dart';
import 'package:soplay/features/cloudstream/presentation/pages/cloudstream_sources_page.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_error_views.dart';

/// Shown when the host is watching from a source (CloudStream `cs:` / Aniyomi
/// `an:`) that requires an on-device plugin this device does not have. Routes the
/// user to the matching sources page to install it.
class PartyPluginRequiredView extends StatelessWidget {
  const PartyPluginRequiredView({
    super.key,
    required this.provider,
    this.installTarget,
    this.onBack,
  });

  /// The party content provider (e.g. `cs:...`, `an:...`).
  final String? provider;

  /// Optional hint from [PartyResolveCapability] about what to install.
  final String? installTarget;

  /// Returns to the lobby (clears the plugin-required block). After installing
  /// the plugin the user taps "Start watching" again to retry the resolve.
  final VoidCallback? onBack;

  bool get _isAniyomi {
    final p = (installTarget ?? provider ?? '').toLowerCase();
    return p.startsWith('an:') || p.contains('aniyomi');
  }

  void _install(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _isAniyomi ? const AniyomiSourcesPage() : const CloudStreamSourcesPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PartyStateView(
      icon: Icons.extension_rounded,
      title: 'watch_party.plugin_required_title'.tr(),
      message: 'watch_party.plugin_required_body'.tr(),
      actionLabel: 'watch_party.install_plugin'.tr(),
      onAction: () => _install(context),
      secondaryLabel: onBack == null ? null : 'general.back'.tr(),
      onSecondary: onBack,
    );
  }
}
