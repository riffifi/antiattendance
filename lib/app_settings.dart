import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettingsStore {
  AppSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _languageKey = 'app_language_v1';

  Future<String?> loadLanguage() async {
    final value = await _storage.read(key: _languageKey);
    return value == 'ru' || value == 'en' ? value : null;
  }

  Future<void> saveLanguage(String? language) async {
    if (language != null && language != 'ru' && language != 'en') {
      throw ArgumentError.value(language, 'language');
    }
    if (language == null) {
      await _storage.delete(key: _languageKey);
    } else {
      await _storage.write(key: _languageKey, value: language);
    }
  }
}
