import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:convert';

import 'app_theme.dart';
import 'schedule_api.dart';

class AppSettingsStore {
  AppSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<ScheduleGroup?> loadMyGroup() async {
    final raw = await _storage.read(key: 'my_group_v1');
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return ScheduleGroup(id: data['id'] as int, name: data['name'] as String);
  }

  Future<void> saveMyGroup(ScheduleGroup? group) async {
    if (group == null) {
      await _storage.delete(key: 'my_group_v1');
    } else {
      if (group.id <= 0 || group.name.trim().isEmpty) {
        throw ArgumentError('Invalid group');
      }
      await _storage.write(
        key: 'my_group_v1',
        value: jsonEncode({'id': group.id, 'name': group.name}),
      );
    }
  }

  Future<bool> loadDaySummaryEnabled() async =>
      await _storage.read(key: 'day_summary_v1') == 'true';
  Future<void> saveDaySummaryEnabled(bool enabled) =>
      _storage.write(key: 'day_summary_v1', value: '$enabled');

  final FlutterSecureStorage _storage;
  static const _languageKey = 'app_language_v1';
  static const _themeKey = 'app_theme_v1';

  Future<AppThemeMode> loadThemeMode() async {
    final value = await _storage.read(key: _themeKey);
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AppThemeMode.light,
    );
  }

  Future<void> saveThemeMode(AppThemeMode mode) async =>
      _storage.write(key: _themeKey, value: mode.name);

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
