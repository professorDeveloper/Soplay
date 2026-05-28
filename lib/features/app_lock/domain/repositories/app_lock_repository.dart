abstract class AppLockRepository {
  bool get isEnabled;
  int get pinLength;
  bool get isBiometricPreferred;

  Future<void> setPin(String pin);
  Future<bool> verifyPin(String pin);
  Future<void> disable();
  Future<void> ensureConsistent();

  Future<bool> isBiometricAvailable();
  Future<void> setBiometricPreferred(bool value);
  Future<bool> authenticateWithBiometrics(String reason);
}
