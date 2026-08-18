import 'package:soplay/core/error/result.dart';

import '../entities/auth_token.dart';
import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<Result<AuthToken>> login(String identifier, String password);

  Future<Result<void>> requestRegisterOtp({
    required String email,
    required String username,
    required String password,
  });

  Future<Result<void>> resendRegisterOtp(String email);

  Future<Result<AuthToken>> verifyRegisterOtp({
    required String email,
    required String code,
  });

  Future<Result<void>> requestPasswordReset(String email);

  Future<Result<AuthToken>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });

  Future<Result<UserEntity>> getProfile();

  Future<void> logout();
}
