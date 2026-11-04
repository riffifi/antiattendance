import 'package:brockmann/brockmann.dart';

import 'campus_design.dart';
import 'about_logo.dart';
import 'frontend/command_bar.dart';
import 'frontend/page_layout.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    CampusNotice.show(
      context,
      message: tr(
        context,
        'Не удалось открыть GitHub. Ссылка скопирована.',
        'Could not open GitHub. Link copied.',
      ),
    );
  }

  Widget _identity(BuildContext context) {
    final t = context.brockmann;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrockmannText('AntiAttendance', role: BrockmannType.heading),
        const SizedBox(height: 8),
        FutureBuilder<String?>(
          future: _version,
          builder: (context, snapshot) => BrockmannText(
            snapshot.data == null ? '—' : 'v${snapshot.data}',
            role: BrockmannType.monoValue,
            color: t.secondary,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        const logo = AboutLogo(size: 72, reserveRotationSpace: false);
        if (bounds.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(16) > 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [logo, const SizedBox(height: 20), details],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            logo,
            const SizedBox(width: 20),
            Expanded(child: details),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(title: Text(tr(context, 'О приложении', 'About'))),
    bottomNavigationBar: CampusCommandBar(
      commands: [
        CampusCommand(
          icon: Icons.link_rounded,
          label: 'GitHub',
          onPressed: _openRepository,
        ),
      ],
    ),
    body: CampusPageBody(
      child: ListView(
        padding: AaPageLayout.insets(context),
        children: [
          BrockmannFeather(index: 0, child: _identity(context)),
          const SizedBox(height: 28),
          BrockmannFeather(
            index: 1,
            child: BrockmannText(
              tr(
                context,
                'Пульс и расписание — в одном месте.',
                'Pulse and your schedule in one place.',
              ),
            ),
          ),
          const SizedBox(height: 32),
          BrockmannFeather(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrockmannText(
                  tr(context, 'Исходный код', 'Source code'),
                  role: BrockmannType.caption,
                  color: context.brockmann.secondary,
                ),
                const SizedBox(height: 8),
                BrockmannPressable(
                  label: 'riffifi/antiattendance',
                  onPressed: _openRepository,
                  builder: (context, pressed) => ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BrockmannText(
                        'riffifi/antiattendance',
                        color: pressed
                            ? context.brockmann.foreground
                            : context.brockmann.accentText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          BrockmannFeather(
            index: 3,
            child: BrockmannText(
              tr(
                context,
                'Пароли не сохраняются. Приложение не является официальным сервисом МИРЭА.',
                'Passwords are not saved. This is not an official MIREA app.',
              ),
              role: BrockmannType.body,
              color: context.brockmann.secondary,
            ),
          ),
        ],
      ),
    ),
  );
}
