import 'package:dio/dio.dart';
import 'package:riasdxd/core/error/result.dart';

import '../../domain/entities/linked_device.dart';
import '../../domain/link_tv_failure.dart';
import '../../domain/repositories/link_tv_repository.dart';
import '../datasources/link_tv_remote_data_source.dart';

class LinkTvRepositoryImpl implements LinkTvRepository {
  final LinkTvRemoteDataSource _remoteDataSource;

  const LinkTvRepositoryImpl(this._remoteDataSource);

  @override
  Future<Result<String?>> approve(String userCode) async {
    try {
      return Success(await _remoteDataSource.approve(userCode));
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(LinkTvFailure(serverMessage: e.toString()));
    }
  }

  @override
  Future<Result<List<LinkedDevice>>> listDevices() async {
    try {
      return Success(await _remoteDataSource.listDevices());
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(LinkTvFailure(serverMessage: e.toString()));
    }
  }

  @override
  Future<Result<void>> unlinkDevice(String id) async {
    try {
      await _remoteDataSource.unlinkDevice(id);
      return const Success(null);
    } on DioException catch (e) {
      return Failure(_failureFrom(e));
    } catch (e) {
      return Failure(LinkTvFailure(serverMessage: e.toString()));
    }
  }

  LinkTvFailure _failureFrom(DioException e) {
    final key = switch (e.response?.statusCode) {
      400 => 'link_tv.error_bad_code',
      401 || 403 => 'link_tv.error_unauthorized',
      404 => 'link_tv.error_not_found',
      409 => 'link_tv.error_already_used',
      410 => 'link_tv.error_expired',
      429 => 'link_tv.error_rate_limited',
      // No response at all means the request never completed — a network problem,
      // not something the user can fix by re-entering the code.
      null => 'link_tv.error_network',
      _ => null,
    };
    final data = e.response?.data;
    final serverMessage =
        data is Map && data['message'] is String && (data['message'] as String).isNotEmpty
            ? data['message'] as String
            : e.message;
    return LinkTvFailure(messageKey: key, serverMessage: serverMessage);
  }
}
