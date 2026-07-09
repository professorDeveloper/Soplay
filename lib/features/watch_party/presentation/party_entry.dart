import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_code_sheet.dart';

/// Navigation payload for `/watch-party` (passed via `GoRouter` `state.extra`).
class WatchPartyArgs {
  const WatchPartyArgs({this.code, this.content});

  final String? code;
  final PartyContent? content;
}

/// Opens the "create a watch party" bottom sheet / dialog. The sheet creates the
/// room (REST + socket) and lets the host copy / share the invite before opening
/// the lobby.
Future<void> showCreatePartySheet(
  BuildContext context, {
  PartyContent? content,
}) {
  return showAdaptiveModal<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PartyCreateSheet(content: content),
  );
}

/// Opens the "join a watch party" bottom sheet / dialog (code entry).
Future<void> showJoinPartySheet(BuildContext context) {
  return showAdaptiveModal<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const PartyJoinSheet(),
  );
}
