/// Target languages the subtitle translator offers.
///
/// The set every configured provider can actually produce. DeepL — the default
/// source — supports all of these, so a translation never fails for the target
/// being unknown. Adding an Azure or Google source later would unlock the
/// Central Asian languages DeepL lacks (Kazakh, Kyrgyz, Tajik); those are left
/// out here on purpose so the list only offers what will work today.
///
/// Each entry is (code, native name).
const List<(String, String)> kSubtitleTranslateLanguages = [
  ('uz', "O'zbekcha"),
  ('ru', 'Русский'),
  ('en', 'English'),
  ('tr', 'Türkçe'),
  ('ar', 'العربية'),
  ('de', 'Deutsch'),
  ('fr', 'Français'),
  ('es', 'Español'),
  ('it', 'Italiano'),
  ('pt', 'Português'),
  ('nl', 'Nederlands'),
  ('pl', 'Polski'),
  ('uk', 'Українська'),
  ('id', 'Bahasa Indonesia'),
  ('ja', '日本語'),
  ('ko', '한국어'),
  ('zh', '中文'),
];
