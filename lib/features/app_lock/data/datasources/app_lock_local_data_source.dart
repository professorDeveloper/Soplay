import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';

class AppLockLocalDataSource {
  AppLockLocalDataSource({
    required HiveService hiveService,
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
  })  : _hive = hiveService,
        _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _localAuth = localAuth ?? LocalAuthentication();

  final HiveService _hive;
  final FlutterSecureStorage _secure;
  final LocalAuthentication _localAuth;

  bool get isEnabled => _hive.isAppLockEnabled;
  int get pinLength => _hive.appLockPinLength;
  bool get isBiometricPreferred => _hive.isAppLockBiometricEnabled;

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    await _secure.write(key: AppConstants.appLockPinSaltSecureKey, value: salt);
    await _secure.write(key: AppConstants.appLockPinHashSecureKey, value: hash);
    await _hive.setAppLockEnabled(true);
    await _hive.setAppLockPinLength(pin.length);
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _secure.read(key: AppConstants.appLockPinSaltSecureKey);
    final stored = await _secure.read(key: AppConstants.appLockPinHashSecureKey);
    if (salt == null || stored == null) {
      await disable();
      return false;
    }
    return _hashPin(pin, salt) == stored;
  }

  Future<void> ensureConsistent() async {
    if (!_hive.isAppLockEnabled) return;
    try {
      final salt =
          await _secure.read(key: AppConstants.appLockPinSaltSecureKey);
      final hash =
          await _secure.read(key: AppConstants.appLockPinHashSecureKey);
      if (salt == null || hash == null) {
        await disable();
      }
    } catch (_) {
      await disable();
    }
  }

  Future<void> disable() async {
    await _secure.delete(key: AppConstants.appLockPinHashSecureKey);
    await _secure.delete(key: AppConstants.appLockPinSaltSecureKey);
    await _hive.setAppLockEnabled(false);
    await _hive.setAppLockBiometricEnabled(false);
  }

  Future<void> setBiometricPreferred(bool value) =>
      _hive.setAppLockBiometricEnabled(value);

  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  String _generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt::$pin::soplay');
    return sha256.convert(bytes).toString();
  }
}
