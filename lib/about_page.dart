import 'campus_design.dart';

import 'package:material_3_expressive/material_3_expressive.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_theme.dart';
import 'external_links.dart';
import 'l10n.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.openGitHub = openWebPage, this.version});

  final Future<bool> Function(Uri) openGitHub;
  final String? version;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static final _repository = Uri.parse(
    'https://github.com/riffifi/antiattendance',
  );

  late final Future<String?> _version = _loadVersion();
  Future<String?> _loadVersion() async {
    if (widget.version != null) return widget.version;
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openRepository() async {
    if (await widget.openGitHub(_repository)) return;
    if (!mounted) return;
    unawaited(
      Clipboard.setData(ClipboardData(text: _repository.toString()))
          .catchError((Object _) {}),
    );
    M3ESnackbar.show(
      context,
      message: tr(
        context,
        'Не удалось открыть GitHub. Ссылка скопирована.',
        'Could not open GitHub. Link copied.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'О приложении', 'About'))),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: CampusButton.icon(
                onPressed: _openRepository,
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                label: const Text('GitHub'),
              ),
            ),
          ),
        ),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - value)),
                  child: child,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 148,
                    height: 148,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          context.palette.selected,
                          context.palette.selected.withValues(alpha: .12),
                        ],
                      ),
                    ),
                    child: Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: context.palette.line),
                        boxShadow: [
                          BoxShadow(
                            color: context.palette.blue.withValues(alpha: .08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SvgPicture.asset(
                        'icon/brand.svg',
                        semanticsLabel: tr(
                          context,
                          'Логотип приложения',
                          'App logo',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'AntiAttendance',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr(
                      context,
                      'Пульс и расписание — в одном месте.',
                      'Pulse and your schedule in one place.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  FutureBuilder<String?>(
                    future: _version,
                    builder: (context, snapshot) => snapshot.data == null
                        ? const SizedBox(height: 20)
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: context.palette.surface,
                                border: Border.all(color: context.palette.line),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'v${snapshot.data}',
                                style: TextStyle(
                                  color: context.palette.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CampusPanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Feature(
                    icon: Icons.qr_code_scanner_rounded,
                    label: tr(context, 'Посещаемость', 'Attendance'),
                  ),
                  _Feature(
                    icon: Icons.calendar_today_outlined,
                    label: tr(context, 'Расписание', 'Schedule'),
                  ),
                  _Feature(
                    icon: Icons.devices_rounded,
                    label: tr(context, 'Передача', 'Transfer'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CampusPanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: context.palette.blue,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tr(
                        context,
                        'Пароли не сохраняются. Приложение не является официальным сервисом МИРЭА.',
                        'Passwords are not saved. This is not an official MIREA app.',
                      ),
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Icon(icon, size: 24, color: context.palette.blue),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.palette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}
