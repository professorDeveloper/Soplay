import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  AppConstants._();

  static String get baseUrl => dotenv.env['BASE_URL'] ?? '';
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

  static const String appLockEnabledKey = 'app_lock_enabled';
  static const String appLockPinLengthKey = 'app_lock_pin_length';
  static const String appLockBiometricKey = 'app_lock_biometric';

  static const String appLockPinHashSecureKey = 'app_lock_pin_hash';
  static const String appLockPinSaltSecureKey = 'app_lock_pin_salt';

  static const String subtitleStyleKey = 'subtitle_style';
}
