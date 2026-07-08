import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';
import '../../features/auth/data/models/user_model.dart';
import '../../features/detail/domain/entities/subtitle_style.dart';

class HiveService {
  final Box _authBox = Hive.box(AppConstants.authBox);
  final Box _settingsBox = Hive.box(AppConstants.settingsBox);

  String? getToken() => _authBox.get(AppConstants.accessTokenKey);
  String? getRefreshToken() => _authBox.get(AppConstants.refreshTokenKey);

  UserModel? getUser() {
    final raw = _authBox.get(AppConstants.userKey);
    if (raw == null) return null;
    return UserModel.fromJson(
      jsonDecode(raw as String) as Map<String, dynamic>,
    );
  }

  Future<void> saveAuth({
    required String accessToken,
    required String refreshToken,
    required UserModel user,
  }) async {
    await saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    await _authBox.put(AppConstants.userKey, jsonEncode(user.toJson()));
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _authBox.put(AppConstants.accessTokenKey, accessToken);
    await _authBox.put(AppConstants.refreshTokenKey, refreshToken);
  }

  Future<void> saveUser(UserModel user) async {
    await _authBox.put(AppConstants.userKey, jsonEncode(user.toJson()));
  }

  Future<void> clearAuth() async {
    await _authBox.delete(AppConstants.accessTokenKey);
    await _authBox.delete(AppConstants.refreshTokenKey);
    await _authBox.delete(AppConstants.userKey);
  }

  bool get isLoggedIn => getToken()?.isNotEmpty == true;

  String getBridgeUrl() =>
      _settingsBox.get('desktop_bridge_url', defaultValue: '') as String;
  Future<void> setBridgeUrl(String url) =>
      _settingsBox.put('desktop_bridge_url', url.trim());

  String? getAniListToken() => _authBox.get(AppConstants.aniListTokenKey);
  bool get isAniListConnected => getAniListToken() != null;

  Future<void> saveAniListToken(String token) async =>
      _authBox.put(AppConstants.aniListTokenKey, token);

  Future<void> clearAniListToken() async =>
      _authBox.delete(AppConstants.aniListTokenKey);

  String? getMalToken() => _authBox.get(AppConstants.malTokenKey);
  bool get isMalConnected => getMalToken() != null;

  Future<void> saveMalToken(String token) async =>
      _authBox.put(AppConstants.malTokenKey, token);

  Future<void> clearMalToken() async =>
      _authBox.delete(AppConstants.malTokenKey);

  String getCurrentProvider() {
    return _settingsBox.get(AppConstants.currentProviderKey, defaultValue: '');
  }

  Future<void> saveCurrentProvider(String providerId) async {
    await _settingsBox.put(AppConstants.currentProviderKey, providerId);
  }

  List<String> getFavoriteProviders() {
    return (_settingsBox.get('favorite_providers') as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
  }

  bool isFavoriteProvider(String id) => getFavoriteProviders().contains(id);

  Future<void> toggleFavoriteProvider(String id) async {
    final list = getFavoriteProviders();
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.add(id);
    }
    await _settingsBox.put('favorite_providers', list);
  }

  String getOpenSubtitlesKey() {
    return _settingsBox.get(AppConstants.openSubtitlesKeyKey, defaultValue: '');
  }

  Future<void> saveOpenSubtitlesKey(String key) async {
    await _settingsBox.put(AppConstants.openSubtitlesKeyKey, key.trim());
  }

  bool get hasSeenShortsRefreshShowcase {
    return _settingsBox.get(
          AppConstants.shortsRefreshShowcaseSeenKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> markShortsRefreshShowcaseSeen() async {
    await _settingsBox.put(AppConstants.shortsRefreshShowcaseSeenKey, true);
  }

  String getLanguage() {
    return _settingsBox.get(AppConstants.languageKey, defaultValue: 'en');
  }

  Future<void> saveLanguage(String langCode) async {
    await _settingsBox.put(AppConstants.languageKey, langCode);
  }

  String getPreferredMediaLang() {
    return _settingsBox.get(
      AppConstants.preferredMediaLangKey,
      defaultValue: AppConstants.defaultMediaLang,
    );
  }

  Future<void> savePreferredMediaLang(String lang) async {
    await _settingsBox.put(AppConstants.preferredMediaLangKey, lang);
  }

  bool get hasTelegramPromoSeen {
    return _settingsBox.get(AppConstants.telegramPromoSeenKey, defaultValue: false) == true;
  }

  Future<void> markTelegramPromoSeen() async {
    await _settingsBox.put(AppConstants.telegramPromoSeenKey, true);
  }

  bool get isAmoledMode {
    return _settingsBox.get(AppConstants.amoledModeKey, defaultValue: false) == true;
  }

  Future<void> setAmoledMode(bool enabled) async {
    await _settingsBox.put(AppConstants.amoledModeKey, enabled);
  }

  bool get hasOnboardingSeen {
    return _settingsBox.get(AppConstants.onboardingSeenKey, defaultValue: false) == true;
  }

  Future<void> markOnboardingSeen() async {
    await _settingsBox.put(AppConstants.onboardingSeenKey, true);
  }

  bool get hasDeeplinkPromptSeen {
    return _settingsBox.get(
          AppConstants.deeplinkPromptSeenKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> markDeeplinkPromptSeen() async {
    await _settingsBox.put(AppConstants.deeplinkPromptSeenKey, true);
  }

  bool get isDeeplinkOptIn {
    return _settingsBox.get(
          AppConstants.deeplinkOptInKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setDeeplinkOptIn(bool value) async {
    await _settingsBox.put(AppConstants.deeplinkOptInKey, value);
  }

  bool get isAppLockEnabled {
    return _settingsBox.get(
          AppConstants.appLockEnabledKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    await _settingsBox.put(AppConstants.appLockEnabledKey, enabled);
  }

  int get appLockPinLength {
    final v = _settingsBox.get(AppConstants.appLockPinLengthKey, defaultValue: 4);
    return (v is int && (v == 4 || v == 6)) ? v : 4;
  }

  Future<void> setAppLockPinLength(int length) async {
    await _settingsBox.put(AppConstants.appLockPinLengthKey, length);
  }

  bool get isAppLockBiometricEnabled {
    return _settingsBox.get(
          AppConstants.appLockBiometricKey,
          defaultValue: false,
        ) ==
        true;
  }

  Future<void> setAppLockBiometricEnabled(bool enabled) async {
    await _settingsBox.put(AppConstants.appLockBiometricKey, enabled);
  }


  bool get useNativeTitleBar =>
      _settingsBox.get('use_native_title_bar', defaultValue: false) == true;

  Future<void> setUseNativeTitleBar(bool value) =>
      _settingsBox.put('use_native_title_bar', value);


  bool get hasSeenPrivateShowcase =>
      _settingsBox.get('private_showcase_seen', defaultValue: false) == true;

  Future<void> markPrivateShowcaseSeen() async =>
      _settingsBox.put('private_showcase_seen', true);

  bool get isPrivateAlwaysAsk =>
      _settingsBox.get('private_always_ask', defaultValue: false) == true;

  Future<void> setPrivateAlwaysAsk(bool value) async =>
      _settingsBox.put('private_always_ask', value);

  String getReaderMode(String contentUrl) {
    return _settingsBox.get('reader_mode::$contentUrl', defaultValue: 'vertical');
  }

  Future<void> saveReaderMode(String contentUrl, String mode) async {
    await _settingsBox.put('reader_mode::$contentUrl', mode);
  }

  bool getReaderRtl(String contentUrl) {
    return _settingsBox.get('reader_rtl::$contentUrl', defaultValue: false) == true;
  }

  Future<void> saveReaderRtl(String contentUrl, bool rtl) async {
    await _settingsBox.put('reader_rtl::$contentUrl', rtl);
  }

  String getReaderBackground() {
    return _settingsBox.get('reader_bg', defaultValue: 'black');
  }

  Future<void> saveReaderBackground(String bg) async {
    await _settingsBox.put('reader_bg', bg);
  }

  SubtitleStyle getSubtitleStyle() {
    final raw = _settingsBox.get(AppConstants.subtitleStyleKey);
    if (raw is String && raw.isNotEmpty) {
      return SubtitleStyle.fromJsonString(raw);
    }
    return SubtitleStyle.defaults();
  }

  Future<void> saveSubtitleStyle(SubtitleStyle style) async {
    await _settingsBox.put(
      AppConstants.subtitleStyleKey,
      style.toJsonString(),
    );
  }
}
