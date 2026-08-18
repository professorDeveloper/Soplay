import 'package:dio/dio.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/auth/data/models/user_model.dart';
import 'package:soplay/features/auth/domain/entities/auth_token.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/history/data/history_sync_service.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final HiveService _hiveService;

  AuthRepositoryImpl(this._remoteDataSource, this._hiveService);

  @override
  Future<Result<AuthToken>> login(String identifier, String password) async {
    try {
      final model = await _remoteDataSource.login(identifier, password);
      if (model.accessToken.isEmpty) {
        return Failure(Exception('Access token topilmadi'));
      }
      await _hiveService.saveAuth(
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
        user: model.user as UserModel,
      );
      return Success(model);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<void>> requestRegisterOtp({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      await _remoteDataSource.requestRegisterOtp(
        email: email,
        username: username,
        password: password,
      );
      return const Success(null);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<void>> resendRegisterOtp(String email) async {
    try {
      await _remoteDataSource.resendRegisterOtp(email);
      return const Success(null);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<AuthToken>> verifyRegisterOtp({
    required String email,
    required String code,
  }) async {
    try {
      final model =
          await _remoteDataSource.verifyRegisterOtp(email: email, code: code);
      if (model.accessToken.isEmpty) {
        return Failure(Exception('Access token topilmadi'));
      }
      await _hiveService.saveAuth(
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
        user: model.user as UserModel,
      );
      return Success(model);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<void>> requestPasswordReset(String email) async {
    try {
      await _remoteDataSource.requestPasswordReset(email);
      return const Success(null);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<AuthToken>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final model = await _remoteDataSource.resetPassword(
        email: email,
        code: code,
        newPassword: newPassword,
      );
      if (model.accessToken.isEmpty) {
        return Failure(Exception('Access token topilmadi'));
      }
      // Stored exactly like a verified registration: the reset issues a real
      // session, and not saving it would leave the user staring at a login
      // screen straight after proving who they are.
      await _hiveService.saveAuth(
        accessToken: model.accessToken,
        refreshToken: model.refreshToken,
        user: model.user as UserModel,
      );
      return Success(model);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<Result<UserEntity>> getProfile() async {
    try {
      final user = await _remoteDataSource.getProfile();
      await _hiveService.saveUser(user);
      return Success(user);
    } on DioException catch (e) {
      return Failure(Exception(_messageFrom(e)));
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _remoteDataSource.logout();
    } on DioException {
      await _clearAccountScopedData();
      return;
    }
    await _clearAccountScopedData();
  }

  /// Tokens are not the only account-scoped state on the device.
  ///
  /// The watch-history sync cursor points at one account's rows; left behind,
  /// the next sign-in resumes from a stranger's position and uploads this
  /// person's viewing into their history.
  ///
  /// The AniList link is account-scoped for the same reason, and worse: its
  /// token writes to a real third-party list, so a leftover one would file the
  /// next person's viewing under a stranger's AniList profile.
  Future<void> _clearAccountScopedData() async {
    await _hiveService.clearAuth();
    if (getIt.isRegistered<HistorySyncService>()) {
      await getIt<HistorySyncService>().clear();
    }
    if (getIt.isRegistered<AnilistService>()) {
      await getIt<AnilistService>().forgetLocal();
    }
    if (getIt.isRegistered<AnilistLinkStore>()) {
      await getIt<AnilistLinkStore>().clear();
    }
  }

  String _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) return msg.first.toString();
    }
    return e.message ?? 'Xatolik yuz berdi';
  }
}
