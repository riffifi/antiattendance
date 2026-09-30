import 'package:flutter/material.dart';

import 'about_page.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'l10n.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.language,
    required this.onLanguageChanged,
  });

  final AppSettingsStore store;
  final String? language;
  final ValueChanged<String?> onLanguageChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String? _language = widget.language;
  bool _saving = false;

  Future<void> _choose(String? language) async {
    if (_saving || language == _language) return;
    setState(() => _saving = true);
    try {
      await widget.store.saveLanguage(language);
      if (!mounted) return;
      setState(() => _language = language);
      widget.onLanguageChanged(language);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось сохранить язык.',
              'Could not save language.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Настройки', 'Settings'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text(
              tr(context, 'Язык приложения', 'App language'),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                'По умолчанию используется язык телефона.',
                'Your phone language is used by default.',
              ),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _Choice(
              title: tr(context, 'Как на телефоне', 'Use phone language'),
              subtitle: tr(context, 'Автоматически', 'Automatic'),
              selected: _language == null,
              onTap: _saving ? null : () => _choose(null),
            ),
            _Choice(
              title: 'Русский',
              selected: _language == 'ru',
              onTap: _saving ? null : () => _choose('ru'),
            ),
            _Choice(
              title: 'English',
              selected: _language == 'en',
              onTap: _saving ? null : () => _choose('en'),
            ),
            const SizedBox(height: 28),
            Text(
              tr(context, 'Приложение', 'App'),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.blue,
                ),
                title: Text(
                  tr(context, 'О AntiAttendance', 'About AntiAttendance'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected ? const Color(0xFFE8EDFC) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Icon(
          selected ? Icons.check_circle_rounded : Icons.circle_outlined,
          color: selected ? AppColors.blue : AppColors.muted,
        ),
        onTap: onTap,
      ),
    ),
  );
}
