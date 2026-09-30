import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _torchOn = false;
  bool _cameraError = false;

  void _updated() => widget.onUpdate(_queue);

  Future<void> _toggleTorch() async {
    try {
      await _camera.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // Keep scanning if the camera has no torch.
    }
  }

  @override
  void dispose() {
    _queue.removeListener(_updated);
    _queue.dispose();
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: (capture) {
              if (_cameraError) setState(() => _cameraError = false);
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null) _queue.accept(value);
              }
            },
            errorBuilder: (context, error) {
              if (!_cameraError) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _cameraError = true);
                });
              }
              return const ColoredBox(color: Colors.black);
            },
          ),
          QueueScanOverlay(
            queue: _queue,
            accounts: widget.accounts,
            torchOn: _torchOn,
            cameraError: _cameraError,
            onTorch: _toggleTorch,
            onClose: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
}

class QueueScanOverlay extends StatelessWidget {
  const QueueScanOverlay({
    super.key,
    required this.queue,
    required this.accounts,
    required this.torchOn,
    this.cameraError = false,
    required this.onTorch,
    required this.onClose,
  });

  final AttendanceQueue queue;
  final List<SavedAccount> accounts;
  final bool torchOn;
  final bool cameraError;
  final VoidCallback onTorch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final panelHeight = (constraints.maxHeight * .36).clamp(130.0, 250.0);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: tr(context, 'Закрыть', 'Close'),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xBB101F36),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tr(context, 'Очередь отметок', 'Attendance queue'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: cameraError ? null : onTorch,
                    icon: Icon(
                      torchOn
                          ? Icons.flashlight_off_rounded
                          : Icons.flashlight_on_rounded,
                    ),
                    tooltip: tr(context, 'Фонарик', 'Flashlight'),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xBB101F36),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, space) {
                  final size = math.max(
                    0.0,
                    math.min(
                      250.0,
                      math.min(space.maxWidth - 52, space.maxHeight - 20),
                    ),
                  );
                  return Center(
                    child: AnimatedBuilder(
                      animation: queue,
                      builder: (context, _) => Container(
                        key: const ValueKey('queue-scan-frame'),
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: cameraError
                                ? const Color(0xFFFFC16B)
                                : queue.remaining == 0
                                ? const Color(0xFF95E6BD)
                                : Colors.white,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: cameraError
                            ? const Icon(
                                Icons.no_photography_rounded,
                                color: Color(0xFFFFC16B),
                                size: 42,
                              )
                            : queue.remaining == 0
                            ? const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF95E6BD),
                                size: 52,
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: queue,
              builder: (context, _) => Container(
                key: const ValueKey('queue-status-panel'),
                height: panelHeight,
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xF2122039),
                  border: Border.all(color: const Color(0x558CA6D5)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cameraError
                                ? tr(
                                    context,
                                    'Камера недоступна',
                                    'Camera unavailable',
                                  )
                                : queue.remaining == 0
                                ? tr(context, 'Все отмечены', 'All confirmed')
                                : trf(
                                    context,
                                    'Осталось {remaining} из {total}',
                                    '{remaining} of {total} remaining',
                                    {
                                      'remaining': queue.remaining,
                                      'total': accounts.length,
                                    },
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (queue.processing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cameraError
                          ? tr(
                              context,
                              'Проверьте разрешение камеры и откройте режим снова.',
                              'Check camera permission and reopen this mode.',
                            )
                          : queue.remaining == 0
                          ? tr(
                              context,
                              'Готово, камеру можно закрыть.',
                              'You can close the camera.',
                            )
                          : tr(
                              context,
                              'Держите QR-код в кадре — оставшиеся аккаунты попробуют ещё раз.',
                              'Keep the QR in view; pending accounts will retry.',
                            ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: accounts.isEmpty
                          ? 0
                          : queue.confirmed.length / accounts.length,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4),
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF95E6BD),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: accounts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final account = accounts[index];
                          final approved = queue.confirmed.contains(account.id);
                          final status =
                              queue.errors[account.id] ??
                              queue.results[account.id]?.message ??
                              tr(context, 'Ждёт отметки', 'Queued');
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                approved
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: approved
                                    ? const Color(0xFF95E6BD)
                                    : Colors.white70,
                                size: 18,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      account.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      trMessage(context, status),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: approved
                                            ? const Color(0xFF95E6BD)
                                            : Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
