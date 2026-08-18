import '../../../../core/error/result.dart';
import '../entities/auth_token.dart';
import '../repositories/auth_repository.dart';

class RequestPasswordResetUseCase {
  final AuthRepository _authRepository;

  RequestPasswordResetUseCase(this._authRepository);

  Future<Result<void>> call(String email) {
    return _authRepository.requestPasswordReset(email);
  }
}

class ResetPasswordUseCase {
  final AuthRepository _authRepository;

  ResetPasswordUseCase(this._authRepository);

  Future<Result<AuthToken>> call({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _authRepository.resetPassword(
      email: email,
      code: code,
      newPassword: newPassword,
    );
  }
}
