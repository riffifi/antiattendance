import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_theme.dart';

class AppSettingsStore {
  AppSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _languageKey = 'app_language_v1';
  static const _themeKey = 'app_theme_v1';
  static const _monetKey = 'app_monet_v1';

  Future<AppThemeMode> loadThemeMode() async {
    final value = await _storage.read(key: _themeKey);
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AppThemeMode.light,
    );
  }

  Future<void> saveThemeMode(AppThemeMode mode) async =>
      _storage.write(key: _themeKey, value: mode.name);

  Future<bool> loadMonetEnabled() async =>
      await _storage.read(key: _monetKey) == 'true';

  Future<void> saveMonetEnabled(bool enabled) async =>
      _storage.write(key: _monetKey, value: '$enabled');

  Future<String?> loadLanguage() async {
    final value = await _storage.read(key: _languageKey);
    return {'ru', 'en', 'fr', 'pt', 'zh'}.contains(value) ? value : null;
  }

  Future<void> saveLanguage(String? language) async {
    if (language != null &&
        !{'ru', 'en', 'fr', 'pt', 'zh'}.contains(language)) {
      throw ArgumentError.value(language, 'language');
    }
    if (language == null) {
      await _storage.delete(key: _languageKey);
    } else {
      await _storage.write(key: _languageKey, value: language);
    }
  }
}
