import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/private_list/presentation/pages/private_unlock_page.dart';

Future<bool> requestPrivateUnlock(BuildContext context) async {
  final lock = getIt<AppLockRepository>();
  final pv = getIt<PrivateListService>();
  final alwaysAsk = getIt<HiveService>().isPrivateAlwaysAsk;

  if (!alwaysAsk && pv.isUnlockedForSession) return true;

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
