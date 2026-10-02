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
  Timer? _finishTimer;

  void _updated() {
    widget.onUpdate(_queue);
    if (_queue.remaining == 0 && _finishTimer == null) {
      unawaited(HapticFeedback.mediumImpact());
      _finishTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          Navigator.of(context).pop();
        }
      });
    }
  }

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
    _finishTimer?.cancel();
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
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0x77000000),
                  ],
                  stops: [0, 0.2, 0.7, 1],
                ),
              ),
            ),
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
                      tr(context, 'Сканировать QR', 'Scan QR'),
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
                      builder: (context, _) => AnimatedContainer(
                        key: const ValueKey('queue-scan-frame'),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
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
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: cameraError
                              ? const Icon(
                                  Icons.no_photography_rounded,
                                  key: ValueKey('camera-error'),
                                  color: Color(0xFFFFC16B),
                                  size: 42,
                                )
                              : queue.remaining == 0
                              ? const Icon(
                                  Icons.check_rounded,
                                  key: ValueKey('scan-complete'),
                                  color: Color(0xFF95E6BD),
                                  size: 52,
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('scan-pending'),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: queue,
              builder: (context, _) => AnimatedContainer(
                key: const ValueKey('queue-status-panel'),
                duration: const Duration(milliseconds: 180),
                height: panelHeight,
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xF2122039),
                  border: Border.all(
                    color: cameraError
                        ? const Color(0x99FFC16B)
                        : queue.remaining == 0
                        ? const Color(0x9995E6BD)
                        : const Color(0x558CA6D5),
                  ),
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
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        cameraError
                            ? tr(
                                context,
                                'Проверьте разрешение камеры и откройте экран снова.',
                                'Check camera permission and reopen this screen.',
                              )
                            : queue.remaining == 0
                            ? tr(
                                context,
                                'Готово, камеру можно закрыть.',
                                'You can close the camera.',
                              )
                            : !queue.hasScanned
                            ? tr(
                                context,
                                'Наведите камеру на QR-код Пульса — отправим отметки сразу.',
                                'Point at a Pulse QR code; attendance sends immediately.',
                              )
                            : queue.processing
                            ? tr(
                                context,
                                'Отправляем отметки. Держите QR-код в кадре.',
                                'Submitting. Keep the QR in view.',
                              )
                            : tr(
                                context,
                                'Держите QR-код в кадре — повторим попытку для остальных.',
                                'Keep the QR in view; pending accounts will retry.',
                              ),
                        key: ValueKey((
                          cameraError,
                          queue.remaining == 0,
                          queue.hasScanned,
                          queue.processing,
                        )),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: accounts.isEmpty
                            ? 0
                            : queue.confirmed.length / accounts.length,
                      ),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF95E6BD),
                        ),
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
