import 'package:riasdxd/core/error/result.dart';

import '../entities/linked_device.dart';

abstract class LinkTvRepository {
  /// Binds the pairing identified by [userCode] to the signed-in account.
  ///
  /// Returns the TV's own label when the server sent one, so the confirmation can
  /// name the device the user just linked.
  Future<Result<String?>> approve(String userCode);

  Future<Result<List<LinkedDevice>>> listDevices();

  Future<Result<void>> unlinkDevice(String id);
}
