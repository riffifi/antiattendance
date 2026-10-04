import 'package:antiattendance/qr_tracking.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera coordinates account for cover scaling and cropping', () {
    expect(
      projectQrCorners(
        const [
          Offset(130, 80),
          Offset(70, 20),
          Offset(70, 80),
          Offset(130, 20),
        ],
        const Size(200, 100),
        const Size(100, 100),
      ),
      const [Offset(20, 20), Offset(80, 20), Offset(80, 80), Offset(20, 80)],
    );
  });
  test('unknown or malformed camera coordinates use the resting frame', () {
    expect(
      projectQrCorners(
        const [Offset.zero],
        const Size(100, 100),
        const Size(100, 100),
      ),
      isEmpty,
    );
    expect(
      projectQrCorners(
        List.filled(4, Offset.zero),
        Size.zero,
        const Size(100, 100),
      ),
      isEmpty,
    );
    expect(
      projectQrCorners(
        List.filled(4, const Offset(double.nan, 1)),
        const Size(100, 100),
        const Size(100, 100),
      ),
      isEmpty,
    );
  });
  testWidgets('tracking resets when a QR disappears and disposes safely', (
    tester,
  ) async {
    final tracker = QrFrameTracker();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrTrackingOverlay(tracker: tracker, color: Colors.blue),
        ),
      ),
    );
    tracker.detect(const [
      Offset(20, 20),
      Offset(80, 20),
      Offset(80, 80),
      Offset(20, 80),
    ], const Size(100, 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tracker.corners, hasLength(4));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tracker.corners, isEmpty);
    await tester.pumpWidget(const SizedBox());
    tracker.dispose();
    expect(tester.takeException(), isNull);
  });
}
