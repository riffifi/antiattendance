import 'qr_tracking.dart';
import 'app_theme.dart';
import 'campus_design.dart';

import 'package:material_3_expressive/material_3_expressive.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
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
  final _tracker = QrFrameTracker();
  final _fallbackKey = GlobalKey();
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
    _tracker.dispose();
    _finishTimer?.cancel();
    _queue.removeListener(_updated);
    _queue.dispose();
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Scaffold(
      backgroundColor: context.palette.paper,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: (capture) {
              if (_cameraError) setState(() => _cameraError = false);
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null) {
                  try {
                    attendanceTokenFromQr(value);
                    _tracker.detect(barcode.corners, capture.size);
                    _queue.accept(value);
                  } on FormatException {
                    /* Unrelated QR codes do not move the frame. */
                  }
                }
              }
            },
            errorBuilder: (context, error) {
              if (!_cameraError) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _cameraError = true);
                });
              }
              return ColoredBox(color: context.palette.paper);
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
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _queue,
              builder: (context, _) => QrTrackingOverlay(
                tracker: _tracker,
                fallbackKey: _fallbackKey,
                color: _queue.remaining == 0
                    ? context.palette.success
                    : context.palette.blue,
              ),
            ),
          ),
          QueueScanOverlay(
            fallbackKey: _fallbackKey,
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
    this.fallbackKey,
    required this.onTorch,
    required this.onClose,
  });

  final GlobalKey? fallbackKey;
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.surface.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    M3EIconButton(
                      suppressInk: true,
                      decoration: M3EIconButtonDecoration(
                        backgroundColor: WidgetStatePropertyAll(
                          context.palette.surface.withValues(alpha: .95),
                        ),
                        foregroundColor: WidgetStatePropertyAll(
                          context.palette.ink,
                        ),
                      ),
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: tr(context, 'Закрыть', 'Close'),
                      variant: M3EIconButtonVariant.tonal,
                    ),
                    Expanded(
                      child: Text(
                        tr(context, 'Сканировать QR', 'Scan QR'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.palette.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    M3EIconButton(
                      suppressInk: true,
                      decoration: M3EIconButtonDecoration(
                        backgroundColor: WidgetStatePropertyAll(
                          context.palette.surface.withValues(alpha: .95),
                        ),
                        foregroundColor: WidgetStatePropertyAll(
                          context.palette.ink,
                        ),
                      ),
                      onPressed: cameraError ? null : onTorch,
                      icon: Icon(
                        torchOn
                            ? Icons.flashlight_off_rounded
                            : Icons.flashlight_on_rounded,
                      ),
                      tooltip: tr(context, 'Фонарик', 'Flashlight'),
                      variant: M3EIconButtonVariant.tonal,
                    ),
                  ],
                ),
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
                      builder: (context, _) => SizedBox(
                        key: fallbackKey,
                        child: CampusScanFrame(
                          key: const ValueKey('queue-scan-frame'),
                          size: size,
                          color: fallbackKey != null
                              ? Colors.transparent
                              : cameraError
                              ? const Color(0xFFFFC16B)
                              : queue.remaining == 0
                              ? context.palette.success
                              : Colors.white,
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
                                ? Icon(
                                    Icons.check_rounded,
                                    key: ValueKey('scan-complete'),
                                    color: context.palette.success,
                                    size: 52,
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('scan-pending'),
                                  ),
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
                  color: context.palette.surface.withValues(alpha: .96),
                  border: Border.all(
                    color: cameraError
                        ? const Color(0x99FFC16B)
                        : queue.remaining == 0
                        ? const Color(0x9995E6BD)
                        : context.palette.line,
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
                            style: TextStyle(
                              color: context.palette.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (queue.processing)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: M3EProgressIndicator.circularWavy(
                              strokeWidth: 2,
                              color: context.palette.ink,
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
                        style: TextStyle(
                          color: context.palette.muted,
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
                      builder: (context, value, _) => TickerMode(
                        enabled:
                            value > 0 &&
                            value < 1 &&
                            !MediaQuery.disableAnimationsOf(context),
                        child: M3EProgressIndicator.linearWavy(
                          value: value,
                          strokeWidth: 4,
                          color: context.palette.success,
                          trackColor: Colors.white24,
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
                                    ? context.palette.success
                                    : context.palette.muted,
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
                                      style: TextStyle(
                                        color: context.palette.ink,
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
                                            ? context.palette.success
                                            : context.palette.muted,
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
