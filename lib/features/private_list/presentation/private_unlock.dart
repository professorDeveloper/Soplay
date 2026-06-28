import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/private_list/presentation/pages/private_unlock_page.dart';

/// Gates access to the LOCKED PRIVATE LIST behind the app-lock credential.
///
/// Returns `true` when the caller may proceed to reveal private content:
///  - already unlocked this session, or
///  - the user just set up a PIN (no lock existed yet), or
///  - the user passed the cancellable [PrivateUnlockPage] verify flow.
///
/// Returns `false` if the user cancels or declines to set up a PIN.
Future<bool> requestPrivateUnlock(BuildContext context) async {
  final lock = getIt<AppLockRepository>();
  final pv = getIt<PrivateListService>();
  final alwaysAsk = getIt<HiveService>().isPrivateAlwaysAsk;

  // When "always ask" is on, every open re-prompts (the per-session unlock is
  // ignored, and we never persist the session flag on success).
  if (!alwaysAsk && pv.isUnlockedForSession) return true;

  // No credential exists yet — the private list is meaningless without one,
  // so prompt the user to create a PIN first.
  if (!lock.isEnabled) {
    final set = await context.push<bool>('/pin-setup');
    if (set != true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('app_lock.private_setup_required'.tr())),
        );
      }
      return false;
    }
    // Creating the PIN authenticates the user for this open. Only persist the
    // session unlock when "always ask" is off.
    if (!alwaysAsk) pv.markUnlocked();
    return true;
  }

  if (!context.mounted) return false;

  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => const PrivateUnlockPage()),
  );
  if (ok == true) {
    if (!alwaysAsk) pv.markUnlocked();
    return true;
  }
  return false;
}
