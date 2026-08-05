import 'package:dio/dio.dart';

import '../models/linked_device_model.dart';

/// The phone half of the RFC-8628 device pairing the TV starts.
///
/// Every call here is account-scoped, so the shared [Dio] must be the authenticated
/// one — `AuthInterceptor` attaches the bearer token and handles the 401 refresh.
class LinkTvRemoteDataSource {
  final Dio dio;

  const LinkTvRemoteDataSource({required this.dio});

  /// Approves a pairing by its public 8-character code. The TV, which polls with a
  /// secret it never showed anyone, picks up the tokens on its next poll.
  Future<String?> approve(String userCode) async {
    final response = await dio.post(
      '/auth/device/approve',
      data: {'user_code': userCode},
    );
    final data = response.data;
    return data is Map ? data['deviceName'] as String? : null;
  }

  Future<List<LinkedDeviceModel>> listDevices() async {
    final response = await dio.get('/auth/devices');
    final data = response.data;
    final devices = data is Map ? data['devices'] : null;
    if (devices is! List) return const [];
    return devices
        .whereType<Map>()
        .map((e) => LinkedDeviceModel.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> unlinkDevice(String id) async {
    await dio.delete('/auth/devices/$id');
  }
}
