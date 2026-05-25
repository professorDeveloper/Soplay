import 'package:soplay/features/app_lock/data/datasources/app_lock_local_data_source.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';

class AppLockRepositoryImpl implements AppLockRepository {
  AppLockRepositoryImpl(this._source);

  final AppLockLocalDataSource _source;

  @override
  bool get isEnabled => _source.isEnabled;

  @override
  int get pinLength => _source.pinLength;

  @override
  bool get isBiometricPreferred => _source.isBiometricPreferred;

  @override
  Future<void> setPin(String pin) => _source.setPin(pin);

  @override
  Future<bool> verifyPin(String pin) => _source.verifyPin(pin);

  @override
  Future<void> disable() => _source.disable();

  @override
  Future<bool> isBiometricAvailable() => _source.isBiometricAvailable();

  @override
  Future<void> setBiometricPreferred(bool value) =>
      _source.setBiometricPreferred(value);

  @override
  Future<bool> authenticateWithBiometrics(String reason) =>
      _source.authenticateWithBiometrics(reason);
}
