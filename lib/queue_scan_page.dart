import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'accounts.dart';
import 'attendance_queue.dart';
import 'l10n.dart';
import 'pulse_api.dart';

class QueueScanPage extends StatefulWidget {
  const QueueScanPage({
    super.key,
    required this.accounts,
    required this.api,
    required this.onUpdate,
  });

  final List<SavedAccount> accounts;
  final PulseApi api;
  final ValueChanged<AttendanceQueue> onUpdate;

  @override
  State<QueueScanPage> createState() => _QueueScanPageState();
}

class _QueueScanPageState extends State<QueueScanPage> {
  final _camera = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 500,
    formats: const [BarcodeFormat.qrCode],
  );
  late final AttendanceQueue _queue = AttendanceQueue(
    accounts: widget.accounts,
    approve: (account, token) => widget.api.approve(token, account.cookie),
  )..addListener(_updated);

  void _updated() => widget.onUpdate(_queue);

  @override
  void dispose() {
    _queue.removeListener(_updated);
    _queue.dispose();
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _camera,
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null) _queue.accept(value);
            }
          },
          errorBuilder: (context, error) => Center(
            child: Text(
              tr(context, 'Камера недоступна', 'Camera unavailable'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: tr(context, 'Закрыть', 'Close'),
                  ),
                  Expanded(
                    child: Text(
                      tr(context, 'Очередь посещаемости', 'Attendance queue'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: () => unawaited(_camera.toggleTorch()),
                    icon: const Icon(Icons.flashlight_on, color: Colors.white),
                    tooltip: tr(context, 'Фонарик', 'Flashlight'),
                  ),
                ],
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _queue,
                builder: (context, _) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xE6181B24),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _queue.remaining == 0
                            ? tr(
                                context,
                                'Все аккаунты подтверждены',
                                'All accounts confirmed',
                              )
                            : tr(
                                context,
                                'Осталось: ${_queue.remaining} из ${widget.accounts.length}',
                                '${_queue.remaining} of ${widget.accounts.length} remaining',
                              ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _queue.remaining == 0
                            ? tr(
                                context,
                                'Можно закрыть камеру.',
                                'You can close the camera.',
                              )
                            : _queue.processing
                            ? tr(
                                context,
                                'Отправляем отметки… Держите QR в кадре.',
                                'Submitting… Keep the QR in view.',
                              )
                            : tr(
                                context,
                                'Держите QR в кадре. Неподтверждённые аккаунты будут повторены.',
                                'Keep the QR in view. Unconfirmed accounts will be retried.',
                              ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: widget.accounts.length,
                          itemBuilder: (context, index) {
                            final account = widget.accounts[index];
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${_queue.confirmed.contains(account.id) ? '✓' : '○'} '
                                '${account.label}: '
                                '${trMessage(context, _queue.errors[account.id] ?? _queue.results[account.id]?.message ?? tr(context, 'В очереди', 'Queued'))}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _queue.confirmed.contains(account.id)
                                      ? const Color(0xFF95E6BD)
                                      : Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
