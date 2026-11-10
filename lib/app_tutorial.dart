import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'l10n.dart';

/// A local, skippable introduction. It never signs in or submits attendance.
class AppTutorial extends StatefulWidget {
  const AppTutorial({super.key, required this.onComplete});
  final Future<void> Function() onComplete;
  @override
  State<AppTutorial> createState() => _AppTutorialState();
}

class _AppTutorialState extends State<AppTutorial> {
  final _pages = PageController();
  int _step = 0;
  bool _finishing = false;
  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        'AA ID',
        tr(
          context,
          'Войдите через МИРЭА один раз. AA ID подключит вашу группу и доступные вам данные. Пароли в приложении вводить не нужно.',
          'Sign in with MIREA once. AA ID connects your group and the data you can access. You do not need to enter a password in the app.',
        ),
      ),
      (
        tr(context, 'Посещаемость', 'Attendance'),
        tr(
          context,
          'Проверьте занятие, выберите людей и нажмите сканирование внизу. Сканируйте QR именно этого занятия. Серые аккаунты требуют повторного входа владельца.',
          'Check the class, select people, then tap Scan at the bottom. Scan that class’s QR code. Grey accounts need their owner to sign in again.',
        ),
      ),
      (
        tr(context, 'Расписание', 'Schedule'),
        tr(
          context,
          'Проводите по экрану или заголовкам, чтобы менять раздел. В расписании выбирайте день, а нажатие на аудиторию откроет карту.',
          'Swipe the screen or its headings to switch sections. Choose a day in Schedule; tap a room to open the map.',
        ),
      ),
      (
        tr(context, 'NFC-пропуска', 'NFC passes'),
        tr(
          context,
          'Откройте пропуска и нажмите значок NFC внизу. Выберите один пропуск или очередь. Владелец выдаёт доступ; для прохода держите экран открытым, а телефон разблокированным. Три точки на панели раскрывают подписи команд.',
          'Open Passes and tap NFC at the bottom. Choose one pass or a queue. The owner grants access; keep the screen open and the phone unlocked at the gate. The app bar’s three dots reveal command labels.',
        ),
      ),
    ];
    return CampusScaffold(
      appBar: CampusAppBar(
        title: Text(tr(context, 'Как пользоваться', 'How to use')),
        automaticallyImplyLeading: false,
        actions: [
          CampusTextAction(
            label: tr(context, 'Пропустить', 'Skip'),
            onPressed: _finishing ? null : _finish,
          ),
        ],
      ),
      bottomNavigationBar: ColoredBox(
        color: context.brockmann.background,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                if (_step > 0)
                  CampusButton.text(
                    onPressed: _finishing
                        ? null
                        : () => _pages.previousPage(
                            duration: context.brockmann.pivotDuration(context),
                            curve: Curves.easeOutCubic,
                          ),
                    child: Text(tr(context, 'Назад', 'Back')),
                  ),
                CampusButton.filled(
                  onPressed: _finishing
                      ? null
                      : _step == steps.length - 1
                      ? _finish
                      : () => _pages.nextPage(
                          duration: context.brockmann.pivotDuration(context),
                          curve: Curves.easeOutCubic,
                        ),
                  child: Text(
                    _step == steps.length - 1
                        ? tr(context, 'Начать', 'Get started')
                        : tr(context, 'Далее', 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Semantics(
              liveRegion: true,
              child: BrockmannText(
                '${_step + 1} / ${steps.length}',
                role: BrockmannType.caption,
                color: context.brockmann.secondary,
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: steps.length,
              onPageChanged: (index) => setState(() => _step = index),
              itemBuilder: (context, i) => ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  BrockmannText(
                    steps[i].$1.toLowerCase(),
                    role: BrockmannType.title,
                  ),
                  const SizedBox(height: 24),
                  BrockmannText(steps[i].$2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
