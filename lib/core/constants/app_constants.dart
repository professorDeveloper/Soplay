import 'dart:convert';

class AppConstants {
  AppConstants._();

  static String? _baseUrl;
  static String get baseUrl => _baseUrl ??= _decode(_obf);

  static const String _obf = 'G0QuQCxKHkE+G1oKMEMJHAAlF1wcRnRdOl9QHjY=';

  static String _decode(String payload) {
    final key = utf8.encode(
      String.fromCharCodes('1v_a2f9_y3k_n1p_0Z0s'.codeUnits.reversed),
    );
    final bytes = base64.decode(payload);
    return utf8.decode(
      List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length]),
    );
  }
  static const String authBox = 'auth_box';
  static const String settingsBox = 'settings_box';
  static const String historyBox = 'history_box';
  static const String downloadBox = 'download_box';
  static const String productsBox = 'products_box';
  static const String cartBox = 'cart_box';
  static const String extractorsBox = 'extractors_box';

  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user';
  static const String themeModeKey = 'theme_mode';
  static const String languageKey = 'language';
  static const String currentProviderKey = 'current_provider';
  static const String shortsRefreshShowcaseSeenKey =
      'shorts_refresh_showcase_seen';
  static const String aniListTokenKey = 'anilist_token';
  static const String malTokenKey = 'mal_token';
  static const String preferredMediaLangKey = 'preferred_media_lang';
  static const String defaultMediaLang = 'sub';
  static const String telegramPromoSeenKey = 'telegram_promo_seen';
  static const String amoledModeKey = 'amoled_mode';
  static const String onboardingSeenKey = 'onboarding_seen';
  static const String deeplinkPromptSeenKey = 'deeplink_prompt_seen';
  static const String deeplinkOptInKey = 'deeplink_opt_in';
  static const String openSubtitlesKeyKey = 'opensubtitles_api_key';

  static const String appLockEnabledKey = 'app_lock_enabled';
  static const String appLockPinLengthKey = 'app_lock_pin_length';
  static const String appLockBiometricKey = 'app_lock_biometric';

  static const String appLockPinHashSecureKey = 'app_lock_pin_hash';
  static const String appLockPinSaltSecureKey = 'app_lock_pin_salt';

  static const String subtitleStyleKey = 'subtitle_style';

  static const String streakBox = 'streak_box';
  static const String streakStateKey = 'streak_state';
}
