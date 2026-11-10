import 'dart:async';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'campus_design.dart';
import 'frontend/command_bar.dart';
import 'frontend/page_layout.dart';
import 'frontend/pass_status_panel.dart';
import 'l10n.dart';
import 'server_api.dart';
import 'server_nfc_controller.dart';
import 'server_sessions.dart';
import 'server_workspace.dart' show ServerMessage, serverError;

String passError(BuildContext context, Object error) {
  if (error is PlatformException) {
    return tr(
      context,
      'Включите NFC. Телефон должен поддерживать эмуляцию карт.',
      'Enable NFC. This phone must support card emulation.',
    );
  }
  if (error is FormatException) {
    return tr(
      context,
      'Пропуск не подключён или изменился. Обновите список и подключите свой пропуск при необходимости.',
      'The pass is missing or changed. Refresh and enroll your own pass if needed.',
    );
  }
  if (error is SessionServerException && error.message.isNotEmpty) {
    return error.detail ?? serverError(context, error);
  }
  return serverError(context, error);
}

class ServerNfcPassPage extends StatefulWidget {
  const ServerNfcPassPage({super.key, required this.api});
  final AaServerApi api;
  @override
  State<ServerNfcPassPage> createState() => _ServerNfcPassPageState();
}

class _ServerNfcPassPageState extends State<ServerNfcPassPage>
    with WidgetsBindingObserver {
  late final controller = ServerNfcController(widget.api);
  final delay = TextEditingController(text: '60');
  String? delayError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    unawaited(controller.refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(controller.stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    controller.dispose();
    delay.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    await controller.stop();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ServerPassEnrollmentPage(
          api: widget.api,
          accountId:
              controller.cards.firstWhere((c) => c['own'] == true)['account_id']
                  as String,
        ),
      ),
    );
    if (mounted) await controller.refresh();
  }

  Future<void> _activate() async {
    final seconds = int.tryParse(delay.text);
    if (!controller.single &&
        (seconds == null || seconds < 1 || seconds > 300)) {
      setState(
        () => delayError = tr(
          context,
          'Укажите задержку от 1 до 300 секунд.',
          'Enter a delay from 1 to 300 seconds.',
        ),
      );
      return;
    }
    setState(() => delayError = null);
    controller.seconds = seconds?.clamp(1, 300) ?? 60;
    await controller.activate();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final enabled = !c.busy && !c.running;
    final current = c.cards
        .where(
          (p) =>
              p['account_id'] ==
              (c.running ? c.status['accountId'] : c.selected.firstOrNull),
        )
        .firstOrNull;
    final own = c.cards.where((p) => p['own'] == true).firstOrNull;
    return CampusScaffold(
      appBar: CampusAppBar(
        title: Text(tr(context, 'NFC-пропуска', 'NFC passes')),
      ),
      bottomNavigationBar: CampusCommandBar(
        commands: [
          CampusCommand(
            icon: c.running ? Icons.stop_rounded : Icons.nfc_rounded,
            label: c.running
                ? tr(context, 'Остановить', 'Stop')
                : c.single
                ? tr(context, 'Активировать пропуск', 'Activate pass')
                : tr(context, 'Запустить очередь', 'Start queue'),
            onPressed: c.busy
                ? null
                : c.running
                ? c.stop
                : c.selected.isEmpty
                ? null
                : _activate,
          ),
          CampusCommand(
            icon: Icons.refresh_rounded,
            label: tr(context, 'Обновить', 'Refresh'),
            onPressed: enabled ? c.refresh : null,
          ),
        ],
      ),
      body: ListView(
        padding: AaPageLayout.insets(context),
        children: [
          BrockmannSegmentedControl<bool>(
            options: const [true, false],
            value: c.single,
            labelFor: (single) => single
                ? tr(context, 'Один пропуск', 'Single pass')
                : tr(context, 'Очередь', 'Queue'),
            onChanged: enabled ? c.setSingle : null,
          ),
          PassStatusPanel(
            idleTitle: tr(context, 'Выберите пропуск', 'Choose a pass'),
            activeDetail: tr(
              context,
              'Активен, пока открыт экран и сервер разрешает доступ.',
              'Active while this screen is open and the server allows access.',
            ),
            running: c.running,
            single: c.single,
            hasPasses: c.cards.isNotEmpty,
            accountLabel:
                (current?['label'] ?? current?['username']) as String?,
            selectedCount: c.selected.length,
            responded: c.status['responded'] == true,
            remainingSeconds:
                (((c.status['remainingMillis'] as num?) ?? 0) / 1000).ceil(),
            presented: (c.status['presented'] as num?)?.toInt() ?? 0,
            total: (c.status['total'] as num?)?.toInt() ?? 0,
          ),
          if (c.busy) const CampusProgress.compact(),
          if (c.error != null)
            ServerMessage(message: passError(context, c.error!)),
          if (delayError != null) ServerMessage(message: delayError!),
          if (!c.single) ...[
            CampusTextField(
              controller: delay,
              label: tr(context, 'Между пропусками', 'Between passes'),
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
            ),
            BrockmannText(
              tr(
                context,
                'Свой пропуск всегда последний в очереди.',
                'Your pass is always last in the queue.',
              ),
              color: context.brockmann.secondary,
            ),
          ],
          AaSectionHeading(
            title: tr(context, 'Доступные пропуска', 'Shared passes'),
          ),
          for (final card in c.cards)
            CampusListItem(
              leading: CampusCheckbox(
                value: c.selected.contains(card['account_id']),
                onChanged: enabled && card['pass_allowed'] == true
                    ? (_) => c.choose(card['account_id'] as String)
                    : null,
              ),
              headline: '${card['label'] ?? card['username'] ?? '—'}',
              supportingText: [
                if (card['group_name'] != null) '${card['group_name']}',
                if (card['own'] == true) tr(context, 'Мой пропуск', 'My pass'),
                if (card['pass_allowed'] != true)
                  tr(context, 'Выключен владельцем', 'Disabled by owner'),
              ].join(' · '),
            ),
          if (c.cards.isEmpty && !c.busy)
            BrockmannText(
              tr(
                context,
                'Вам пока не открыли доступ',
                'No passes shared with you yet',
              ),
              color: context.brockmann.secondary,
            ),
          if (own != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: CampusButton.text(
                onPressed: enabled && own['pass_allowed'] == true
                    ? _enroll
                    : null,
                child: Text(
                  tr(
                    context,
                    'Подключить свой пропуск',
                    'Enroll your own pass',
                  ),
                ),
              ),
            ),
          BrockmannText(
            tr(
              context,
              'Держите приложение открытым и телефон разблокированным. Результат прохода проверяйте на турникете. Разрешения перепроверяются во время работы.',
              'Keep this screen open and your phone unlocked. Check admission at the gate. Permissions are rechecked while active.',
            ),
            color: context.brockmann.secondary,
          ),
        ],
      ),
    );
  }
}

class ServerPassEnrollmentPage extends StatefulWidget {
  const ServerPassEnrollmentPage({
    super.key,
    required this.api,
    required this.accountId,
  });
  final AaServerApi api;
  final String accountId;
  @override
  State<ServerPassEnrollmentPage> createState() =>
      _ServerPassEnrollmentPageState();
}

class _ServerPassEnrollmentPageState extends State<ServerPassEnrollmentPage> {
  final code = TextEditingController();
  bool busy = false;
  String? message;
  Object? error;
  DateTime? retryAt;
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (busy || (retryAt?.isAfter(DateTime.now()) ?? false)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.sendPassCode();
      if (!mounted) return;
      final state = result['state'];
      if (!['code_sent', 'wait', 'unavailable'].contains(state)) {
        throw const FormatException();
      }
      setState(() {
        message = state == 'unavailable'
            ? tr(
                context,
                'Нет цифрового пропуска или способа подтверждения МИРЭА.',
                'No digital pass or MIREA verification method is available.',
              )
            : state == 'wait'
            ? tr(
                context,
                'Подождите перед повторным запросом кода.',
                'Wait before requesting another code.',
              )
            : tr(
                context,
                'Код отправлен способом подтверждения МИРЭА.',
                'The code was sent using your MIREA verification method.',
              );
        final seconds = result['retry_at'];
        retryAt =
            seconds is num &&
                seconds.isFinite &&
                seconds > 0 &&
                seconds < 253402300799
            ? DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round())
            : DateTime.now().add(const Duration(seconds: 60));
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          if (e is SessionServerException && (e.retryAfterSeconds ?? 0) > 0) {
            retryAt = DateTime.now().add(
              Duration(seconds: e.retryAfterSeconds!.clamp(1, 86400)),
            );
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        timer?.cancel();
        if (retryAt != null) {
          timer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!retryAt!.isAfter(DateTime.now())) {
              timer?.cancel();
              if (mounted) setState(() {});
            }
          });
        }
      }
    }
  }

  Future<void> _issue() async {
    if (busy || !RegExp(r'^[0-9]{6}$').hasMatch(code.text)) return;
    final entered = code.text;
    Object? previous;
    var attempted = false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      previous = (await widget.api.digitalPass(widget.accountId))['number'];
      if (!mounted) return;
      attempted = true;
      final issued = await widget.api.issuePass(entered);
      if (issued['account_id'] != widget.accountId ||
          issued['number'] is! String) {
        throw const FormatException();
      }
      if (!mounted) return;
      code.clear();
      Navigator.of(context).pop();
    } catch (e) {
      // An interrupted mutation may already have succeeded. Read, never reissue.
      if (attempted) {
        try {
          final saved = await widget.api.digitalPass(widget.accountId);
          if (mounted &&
              saved['number'] is String &&
              saved['number'] != previous) {
            code.clear();
            Navigator.of(context).pop();
            return;
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          error = e;
          if (attempted) {
            message = tr(
              context,
              'Выпуск не подтверждён. Проверьте сохранённый пропуск перед повторным выпуском.',
              'Issuance was not confirmed. Check the saved pass before issuing again.',
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(
      title: Text(
        tr(context, 'Подключить свой пропуск', 'Enroll your own pass'),
      ),
    ),
    body: ListView(
      padding: AaPageLayout.insets(context),
      children: [
        BrockmannText(
          tr(
            context,
            'Подтвердите выпуск своим кодом МИРЭА. Повторный выпуск может изменить привязку пропуска.',
            'Confirm enrollment with your MIREA code. Issuing again may change the pass binding.',
          ),
          color: context.brockmann.secondary,
        ),
        const SizedBox(height: 24),
        CampusButton.text(
          onPressed: busy || (retryAt?.isAfter(DateTime.now()) ?? false)
              ? null
              : _send,
          child: Text(tr(context, 'Получить код', 'Get code')),
        ),
        if (message != null) ServerMessage(message: message!),
        if (retryAt != null && retryAt!.isAfter(DateTime.now()))
          BrockmannText(
            '${tr(context, 'Повторить', 'Retry')} · ${TimeOfDay.fromDateTime(retryAt!).format(context)}',
            color: context.brockmann.secondary,
          ),
        if (error != null) ServerMessage(message: passError(context, error!)),
        CampusTextField(
          controller: code,
          label: tr(context, 'Код подтверждения', 'Verification code'),
          enabled: !busy,
          keyboardType: TextInputType.number,
          obscureText: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        if (busy) const CampusProgress.compact(),
        CampusButton.filled(
          onPressed: busy || code.text.length != 6 ? null : _issue,
          child: Text(tr(context, 'Подключить пропуск', 'Enroll a pass')),
        ),
      ],
    ),
  );
}
