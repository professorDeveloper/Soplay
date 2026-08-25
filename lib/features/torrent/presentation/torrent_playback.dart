import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/torrent/torrent_engine.dart';
import 'package:soplay/core/torrent/torrent_status.dart';
import 'package:soplay/features/torrent/data/torrent_trackers.dart';
import 'package:soplay/features/torrent/domain/entities/torrent_result.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_consent_dialog.dart';
import 'package:soplay/features/torrent/presentation/widgets/torrent_file_picker_sheet.dart';

/// A torrent that is ready to play.
class TorrentStreamHandle {
  const TorrentStreamHandle({
    required this.url,
    required this.hash,
    required this.file,
    required this.title,
  });

  /// A plain, seekable `http://127.0.0.1:…` URL. The player has no idea it is
  /// a torrent, which is the entire design.
  final Uri url;

  final String hash;
  final TorrentFileEntry file;

  /// What to show as the title — the chosen file, not the torrent, since a
  /// season pack's torrent name says nothing about which episode is playing.
  final String title;
}

/// Turns a search result into something the player can open.
///
/// The sequence, and why each step is here:
///
///   1. **Platform check.** The engine is Android-only; elsewhere the feature
///      should be absent rather than fail.
///   2. **Consent.** See [TorrentConsent] — a torrent uploads from the user's
///      device, which nothing else in the app does.
///   3. **Start the server**, attaching the public tracker list. Without those
///      trackers a magnet from an indexer often has no announce URL at all and
///      falls back to DHT alone.
///   4. **Add the link and wait for metadata.** A magnet has no file list until
///      the swarm answers. Reading it immediately is the classic bug — it
///      returns null and the stream URL is built from nothing.
///   5. **Pick a file** when the torrent holds more than one video.
///
/// Steps 3–4 run behind a progress sheet that reports what is actually
/// happening, because "fetching file list from the swarm" can genuinely take
/// twenty seconds on a thin torrent and a bare spinner reads as a hang.
abstract final class TorrentPlayback {
  static Future<TorrentStreamHandle?> prepare(
    BuildContext context,
    TorrentResult result, {
    required TorrentEngine engine,
  }) async {
    if (result.health == SwarmHealth.dead) {
      _toast(ScaffoldMessenger.maybeOf(context), 'torrent.dead_warning'.tr());
      return null;
    }

    final link = result.engineLink(
      extraTrackers: TorrentTrackers.forIndexer(result.indexerId),
    );
    if (link == null) return null;

    return prepareLink(
      context,
      link,
      engine: engine,
      title: result.title,
      trackers: TorrentTrackers.forIndexer(result.indexerId),
    );
  }

  /// The same flow starting from a bare magnet or `.torrent` URL.
  ///
  /// Split out from [prepare] because a torrent does not only arrive from
  /// Sozo's own search: CloudStream plugins return magnets as extractor links,
  /// and those deserve the identical treatment — consent, tracker injection,
  /// metadata wait, file picker — rather than a second, worse implementation.
  static Future<TorrentStreamHandle?> prepareLink(
    BuildContext context,
    String link, {
    required TorrentEngine engine,
    String? title,
    List<String> trackers = TorrentTrackers.defaults,
  }) async {
    if (!engine.isSupported) {
      _toast(ScaffoldMessenger.maybeOf(context), 'torrent.unsupported'.tr());
      return null;
    }

    if (!await TorrentConsent.ensure(context)) return null;
    if (!context.mounted) return null;

    // Captured before the awaits. Everything after this point runs across
    // async gaps, and re-reading them from `context` there is the classic way
    // to touch a disposed element when the user leaves mid-preparation.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    final progress = _PreparationProgress();
    // Non-dismissible only for the moment the sheet is up; the sheet itself
    // offers a cancel, so the user is never trapped waiting on a dead swarm.
    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PreparationSheet(progress: progress),
    ));

    try {
      progress.message = 'torrent.preparing'.tr();

      await engine.ensureStarted(trackers: trackers);
      if (progress.cancelled) return null;

      final added = await engine.add(link, title: title);
      if (progress.cancelled) return null;

      progress.message = 'torrent.fetching_metadata'.tr();

      final status = await engine.awaitMetadata(
        added.hash,
        onProgress: (s) {
          progress.peers = s.activePeers ?? s.totalPeers;
          if (s.label.isNotEmpty) progress.detail = s.label;
        },
      );
      if (progress.cancelled) {
        await engine.drop(status.hash);
        return null;
      }

      final videos = status.videoFiles;
      if (videos.isEmpty) {
        _closeSheet(navigator);
        _toast(messenger, 'torrent.no_results'.tr());
        await engine.drop(status.hash);
        return null;
      }

      _closeSheet(navigator);
      if (!context.mounted) return null;

      TorrentFileEntry file = videos.first;
      if (videos.length > 1) {
        final picked = await TorrentFilePickerSheet.show(context, videos);
        if (picked == null) {
          // Backing out of the picker is a cancel, so stop the swarm rather
          // than leaving it downloading in the background.
          await engine.drop(status.hash);
          return null;
        }
        file = picked;
      }

      return TorrentStreamHandle(
        url: engine.streamUri(status.hash, file),
        hash: status.hash,
        file: file,
        title: file.name,
      );
    } on TimeoutException {
      _closeSheet(navigator);
      _toast(messenger, 'torrent.metadata_timeout'.tr());
      return null;
    } catch (_) {
      _closeSheet(navigator);
      _toast(messenger, 'torrent.engine_failed'.tr());
      return null;
    } finally {
      progress.dispose();
    }
  }

  static void _closeSheet(NavigatorState navigator) {
    if (navigator.mounted && navigator.canPop()) navigator.pop();
  }

  static void _toast(ScaffoldMessengerState? messenger, String message) {
    if (messenger == null || !messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

/// Shared state between the preparation steps and the sheet showing them.
class _PreparationProgress extends ChangeNotifier {
  String _message = '';
  String? _detail;
  int? _peers;
  bool cancelled = false;

  String get message => _message;
  set message(String value) {
    _message = value;
    notifyListeners();
  }

  String? get detail => _detail;
  set detail(String? value) {
    _detail = value;
    notifyListeners();
  }

  int? get peers => _peers;
  set peers(int? value) {
    _peers = value;
    notifyListeners();
  }
}

class _PreparationSheet extends StatelessWidget {
  const _PreparationSheet({required this.progress});

  final _PreparationProgress progress;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: ListenableBuilder(
          listenable: progress,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                progress.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // The peer count is the honest signal that something is
              // happening: metadata arrives the moment one peer answers, so a
              // rising number means progress and a stuck zero means the swarm
              // is empty — which a spinner alone can never say.
              if (progress.peers != null) ...[
                const SizedBox(height: 6),
                Text(
                  'torrent.stats_peers'.tr(args: ['${progress.peers}']),
                  style: TextStyle(color: AppColors.textHint, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  progress.cancelled = true;
                  Navigator.of(context).pop();
                },
                child: Text(
                  'general.cancel'.tr(),
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
