import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Container(
              height: 160,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.deepBlue, AppColors.blue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Center(
                child: Container(
                  width: 96,
                  height: 96,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: SvgPicture.asset('icon/brand.svg'),
                ),
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'AntiAttendance',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                'Один удобный экран для посещаемости, расписания и доверенных аккаунтов.',
                'One simple place for attendance, schedules, and trusted accounts.',
              ),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 30),
            _Feature(
              icon: Icons.qr_code_scanner_rounded,
              title: tr(context, 'Посещаемость', 'Attendance'),
              description: tr(
                context,
                'Сканируйте QR один раз или держите камеру открытой, пока все выбранные аккаунты не получат подтверждение.',
                'Scan once, or keep the camera open until all selected accounts are confirmed.',
              ),
            ),
            _Feature(
              icon: Icons.calendar_month_rounded,
              title: tr(context, 'Расписание', 'Schedule'),
              description: tr(
                context,
                'Выберите группу МИРЭА и смотрите пары вместе с подтверждениями, сохранёнными на этом устройстве.',
                'Choose a MIREA group and see classes with confirmations saved on this device.',
              ),
            ),
            _Feature(
              icon: Icons.devices_rounded,
              title: tr(context, 'Передача', 'Transfer'),
              description: tr(
                context,
                'Передавайте сохранённые сессии доверенным телефонам рядом или через защищённый QR.',
                'Transfer saved sessions to trusted phones nearby or through an encrypted QR.',
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        'Пароли не сохраняются. Сессии и история подтверждений хранятся на устройстве. AntiAttendance — независимое приложение, не официальный сервис МИРЭА.',
                        'Passwords are not saved. Sessions and confirmation history stay on your device. AntiAttendance is an independent app, not an official MIREA service.',
                      ),
                      style: const TextStyle(fontSize: 13, height: 1.4),
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
  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE8EDFC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.blue, size: 23),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
