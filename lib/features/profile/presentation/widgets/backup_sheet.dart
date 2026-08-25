import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/data/backup_service.dart';

/// Export and restore, in one place.
///
/// The two halves are deliberately not symmetrical in tone. Exporting is
/// harmless and immediate. Restoring writes over live data, so it asks first
/// and then says exactly how many values it wrote — a silent "done" after a
/// restore leaves the user with no way to tell a working backup from an empty
/// one until they go looking for something that is not there.
class BackupSheet extends StatefulWidget {
  const BackupSheet._();

  static Future<void> show(BuildContext context) {
    return showAdaptiveModal<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const BackupSheet._(),
    );
  }

  @override
  State<BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<BackupSheet> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await getIt<BackupService>().export();
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'backup.file_subject'.tr(),
      );
    } catch (e) {
      if (mounted) _say('backup.export_failed'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    // Asked before the picker, not after. Once a file is chosen the natural
    // expectation is that something happens, and a confirmation at that point
    // reads as an obstacle rather than a safeguard.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('backup.restore'.tr()),
        content: Text('backup.restore_warning'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('backup.restore'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // `FileType.any` on purpose: a .json filter is honoured inconsistently
      // across Android file providers, and the common failure is a picker that
      // greys out the very file the user just saved.
      final picked = await FilePicker.pickFiles(type: FileType.any);
      final path = picked?.files.single.path;
      if (path == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final summary = await getIt<BackupService>().import(File(path));
      if (!mounted) return;
      setState(() => _busy = false);
      if (!summary.ok) {
        _say(
          summary.error == 'too_new'
              ? 'backup.too_new'.tr()
              : 'backup.not_a_backup'.tr(),
        );
        return;
      }
      _say('backup.restored'.tr(args: ['${summary.restored}']));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _say('backup.restore_failed'.tr());
      }
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(
              children: [
                const Icon(Icons.backup_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'backup.title'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'backup.subtitle'.tr(),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.ios_share_rounded),
            title: Text('backup.export'.tr()),
            subtitle: Text('backup.export_desc'.tr()),
            onTap: _export,
          ),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.restore_rounded),
            title: Text('backup.restore'.tr()),
            subtitle: Text('backup.restore_desc'.tr()),
            onTap: _import,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
