import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';

/// Result of asking whether THIS device can turn a party's content identity
/// into a playable stream.
class PartyResolveCapability {
  /// True when the device can resolve the stream on its own.
  final bool ok;

  /// Machine-readable reason when [ok] is false
  /// (`unsupported_platform` | `plugin_missing`).
  final String? reason;

  /// Which extension family is required (`cloudstream` | `aniyomi`), so the UI
  /// can route the user to the right install screen.
  final String? installTarget;

  const PartyResolveCapability({
    required this.ok,
    this.reason,
    this.installTarget,
  });

  static const PartyResolveCapability allowed =
      PartyResolveCapability(ok: true);
}

/// Decides whether a party guest can resolve the host's content locally.
///
/// The socket only ships identity (never a stream URL), so every device must
/// resolve for itself. On-device extension providers (`cs:` = CloudStream,
/// `an:` = Aniyomi) only work if the matching plugin is installed here. All
/// other providers go through the JS extractor / server resolve path, which is
/// always available.
class PartyResolveGate {
  const PartyResolveGate._();

  static Future<PartyResolveCapability> canResolve(String? provider) async {
    final id = provider?.trim() ?? '';
    if (id.isEmpty) return PartyResolveCapability.allowed;

    if (id.startsWith('cs:')) {
      return _checkInstalled(
        installTarget: 'cloudstream',
        isSupported: CloudStreamChannel.isSupported,
        loadInstalled: CloudStreamChannel.ensureLoaded,
        fullId: id,
      );
    }
    if (id.startsWith('an:')) {
      return _checkInstalled(
        installTarget: 'aniyomi',
        isSupported: AniyomiChannel.isSupported,
        loadInstalled: AniyomiChannel.ensureLoaded,
        fullId: id,
      );
    }

    // JS extractor / server resolve — always available.
    return PartyResolveCapability.allowed;
  }

  static Future<PartyResolveCapability> _checkInstalled({
    required String installTarget,
    required bool isSupported,
    required Future<List<dynamic>> Function() loadInstalled,
    required String fullId,
  }) async {
    if (!isSupported) {
      return PartyResolveCapability(
        ok: false,
        reason: 'unsupported_platform',
        installTarget: installTarget,
      );
    }
    try {
      // `ensureLoaded` forces the native side to load plugins and returns the
      // installed provider list; each entry carries the same prefixed `id`
      // (e.g. `cs:foo`) the app uses everywhere.
      final installed = await loadInstalled();
      final present = installed.any((e) =>
          e is Map && (e['id']?.toString().trim() ?? '') == fullId);
      if (present) return PartyResolveCapability.allowed;
    } catch (_) {
      // Fall through to plugin-missing.
    }
    return PartyResolveCapability(
      ok: false,
      reason: 'plugin_missing',
      installTarget: installTarget,
    );
  }
}
