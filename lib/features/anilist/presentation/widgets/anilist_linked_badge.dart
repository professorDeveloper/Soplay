import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';

/// The AniList mark on a title that is already linked to an AniList entry.
///
/// Linking is what makes tracking work at all — a source title rarely matches
/// AniList exactly — but until now the link was invisible outside the AniList
/// screens, so there was no way to tell from a result whether watching it would
/// count. This is that signal.
///
/// Renders nothing when there is no link, so it costs a search grid nothing in
/// the common case.
class AnilistLinkedBadge extends StatelessWidget {
  const AnilistLinkedBadge({
    super.key,
    required this.contentUrl,
    this.provider,
    this.size = 15,
  });

  final String contentUrl;

  /// The source the result came from. Falls back to the active one, which is
  /// correct for a single-source search and wrong for a cross-source grid —
  /// hence cross search passes each hit's own provider.
  final String? provider;

  final double size;

  @override
  Widget build(BuildContext context) {
    if (contentUrl.trim().isEmpty) return const SizedBox.shrink();
    if (!getIt.isRegistered<AnilistLinkStore>()) return const SizedBox.shrink();

    final source = provider ?? _activeProvider();
    if (source == null || source.isEmpty) return const SizedBox.shrink();

    final mediaId = getIt<AnilistLinkStore>().mediaIdFor(source, contentUrl);
    if (mediaId == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
      ),
      child: AnilistLogo(size: size, radius: 4),
    );
  }

  static String? _activeProvider() {
    if (!getIt.isRegistered<ProviderManager>()) return null;
    return getIt<ProviderManager>().currentProviderId;
  }
}
