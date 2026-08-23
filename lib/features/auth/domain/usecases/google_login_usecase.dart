import '../../../../core/error/result.dart';
import '../entities/auth_token.dart';
import '../repositories/auth_repository.dart';

class GoogleLoginUseCase {
  final AuthRepository _authRepository;
  GoogleLoginUseCase(this._authRepository);
  Future<Result<AuthToken>> call(String idToken) {
    return _authRepository.loginWithGoogle(idToken);
  }
}
