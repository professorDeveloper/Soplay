import 'package:riasdxd/core/error/result.dart';
import 'package:riasdxd/features/app_updater/domain/entities/app_version_check.dart';

abstract class AppUpdaterRepository {
  Future<Result<AppVersionCheck>> check({
    required String platform,
    required int currentVersion,
  });
}
