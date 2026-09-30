import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'l10n.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'О приложении', 'About'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          children: [
            Center(
              child: Container(
                width: 112,
                height: 112,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x17315DDE),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: SvgPicture.asset('icon/brand.svg'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'AntiAttendance',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              tr(
                context,
                'Пульс и расписание — в одном месте.',
                'Pulse and your schedule in one place.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 15),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _FeatureChip(
                  icon: Icons.qr_code_scanner_rounded,
                  label: tr(context, 'Посещаемость', 'Attendance'),
                ),
                _FeatureChip(
                  icon: Icons.calendar_month_rounded,
                  label: tr(context, 'Расписание', 'Schedule'),
                ),
                _FeatureChip(
                  icon: Icons.devices_rounded,
                  label: tr(context, 'Передача', 'Transfer'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.deepBlue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr(
                        context,
                        'Пароли не сохраняются. Приложение не является официальным сервисом МИРЭА.',
                        'Passwords are not saved. This is not an official MIREA app.',
                      ),
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://github.com/riffifi/antiattendance'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('GitHub'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, color: AppColors.blue, size: 18),
    label: Text(label),
    backgroundColor: Colors.white,
    side: const BorderSide(color: AppColors.line),
  );
}
