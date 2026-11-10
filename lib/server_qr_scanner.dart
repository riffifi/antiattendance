import 'dart:async';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'campus_design.dart';
import 'frontend/command_bar.dart';
import 'l10n.dart';
import 'pulse_api.dart';
import 'qr_tracking.dart';
import 'server_api.dart';
import 'server_scan_queue.dart';
import 'server_workspace.dart' show ServerMessage, serverError;

class ServerQrScanner extends StatefulWidget {
  const ServerQrScanner({
    super.key,
    required this.api,
    required this.people,
    required this.lessonStart,
  });
  final AaServerApi api;
  final List<Map<String, dynamic>> people;
  final int lessonStart;
  @override
  State<ServerQrScanner> createState() => _ServerQrScannerState();
}

class _ServerQrScannerState extends State<ServerQrScanner>
    with WidgetsBindingObserver {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
  );
  final _tracker = QrFrameTracker();
  late final _queue = ServerScanQueue(
    api: widget.api,
    people: widget.people,
    lessonStart: widget.lessonStart,
  );
  bool _torch = false;
  String? _hint;
  int _confirmed = 0;
  bool _blocked = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queue.addListener(_updated);
  }

  void _updated() {
    if (!mounted) return;
    if (_queue.blocked && !_blocked) {
      BrockmannFeedbackScope.play(context, BrockmannSound.reject);
    } else if (_queue.confirmed > _confirmed) {
      BrockmannFeedbackScope.play(context, BrockmannSound.confirm);
    }
    _confirmed = _queue.confirmed;
    _blocked = _queue.blocked;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _queue.paused = state != AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _queue.removeListener(_updated);
    _queue.dispose();
    _tracker.dispose();
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _close() =>
      Navigator.of(context)
          .pop(Map<String, Map<String, dynamic>>.from(_queue.results));
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_queue.processing,
    child: CampusScaffold(
      appBar: CampusAppBar(
        compact: true,
        title: Text(tr(context, 'Сканировать QR', 'Scan QR')),
        leading: CampusTextAction(
          icon: Icons.close_rounded,
          label: tr(context, 'Закрыть', 'Close'),
          onPressed: _queue.processing ? null : _close,
        ),
      ),
      bottomNavigationBar: CampusCommandBar(
        commands: [
          CampusCommand(
            icon: _torch
                ? Icons.flashlight_off_rounded
                : Icons.flashlight_on_rounded,
            label: tr(context, 'Фонарик', 'Flashlight'),
            onPressed: () async {
              try {
                await _camera.toggleTorch();
                if (mounted) setState(() => _torch = !_torch);
              } catch (_) {}
            },
          ),
          if (_queue.blocked && _queue.canRetry)
            CampusCommand(
              icon: Icons.refresh_rounded,
              label: tr(context, 'Повторить', 'Retry'),
              onPressed: _queue.retry,
            ),
          CampusCommand(
            icon: Icons.check_rounded,
            label: tr(context, 'Готово', 'Done'),
            onPressed: _queue.processing ? null : _close,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, bounds) => Column(
          children: [
            Expanded(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _camera,
                      fit: BoxFit.cover,
                      onDetect: (capture) {
                        for (final code in capture.barcodes) {
                          final raw = code.rawValue;
                          if (raw == null) continue;
                          try {
                            attendanceTokenFromQr(raw);
                          } on FormatException {
                            if (_hint == null) {
                              setState(
                                () => _hint = tr(
                                  context,
                                  'Нужен QR-код посещаемости.',
                                  'Scan an attendance QR code.',
                                ),
                              );
                            }
                            continue;
                          }
                          if (_hint != null) setState(() => _hint = null);
                          _tracker.detect(code.corners, capture.size);
                          unawaited(_queue.accept(raw));
                          break;
                        }
                      },
                      errorBuilder: (context, _) => ColoredBox(
                        color: context.brockmann.surface,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: BrockmannText(
                              tr(
                                context,
                                'Камера недоступна. Вернитесь и вставьте ссылку.',
                                'Camera unavailable. Go back and paste the link.',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    QrTrackingOverlay(
                      tracker: _tracker,
                      color: _queue.remaining == 0
                          ? const Color(0xff73d5ab)
                          : Colors.white,
                    ),
                  ],
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: bounds.maxHeight * .42),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                children: [
                  Semantics(
                    liveRegion: true,
                    child: BrockmannText(
                      _queue.remaining == 0
                          ? tr(context, 'Все отмечены', 'All confirmed')
                          : trf(
                              context,
                              'Осталось {remaining} из {total}',
                              '{remaining} of {total} remaining',
                              {
                                'remaining': _queue.remaining,
                                'total': widget.people.length,
                              },
                            ),
                      role: BrockmannType.value,
                    ),
                  ),
                  if (_queue.processing) const CampusProgress.linear(),
                  if (_hint != null)
                    ServerMessage(message: _hint!, isError: false),
                  if (_queue.error != null)
                    ServerMessage(
                      message: _queue.error is FormatException
                          ? tr(
                              context,
                              'Ответ не подтверждён. Проверьте результаты перед повторной попыткой.',
                              'The result is uncertain. Check attendance before retrying.',
                            )
                          : serverError(context, _queue.error!),
                    ),
                  for (final person in widget.people)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BrockmannText(
                            '${person['label'] ?? person['username'] ?? '—'}',
                          ),
                          BrockmannText(
                            '${_queue.results[person['id']]?['message'] ?? (_queue.processing ? tr(context, 'Подождите…', 'Please wait…') : tr(context, 'В очереди', 'Queued'))}',
                            role: BrockmannType.caption,
                            color: context.brockmann.secondary,
                          ),
                        ],
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
