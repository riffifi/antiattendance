import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/attendance_queue.dart';
import 'package:antiattendance/pulse_api.dart';
import 'package:antiattendance/queue_scan_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (size, scale) in [
    (const Size(320, 568), 1.0),
    (const Size(360, 480), 1.0),
    (const Size(320, 568), 1.4),
    (const Size(320, 480), 1.4),
  ]) {
    testWidgets(
      'queue panel stays below scan target at ${size.width}×${size.height}, text $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final accounts = [
          for (var i = 0; i < 16; i++)
            SavedAccount(
              id: '$i',
              label: 'Very long account name for student $i',
              cookie: '$i',
            ),
        ];
        final queue = AttendanceQueue(
          accounts: accounts,
          approve: (_, _) async => const ApprovalResult(
            ApprovalState.approved,
            'Присутствие подтверждено',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: QueueScanOverlay(
                  queue: queue,
                  accounts: accounts,
                  torchOn: false,
                  onTorch: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        final frame = tester.getRect(
          find.byKey(const ValueKey('queue-scan-frame')),
        );
        final panel = tester.getRect(
          find.byKey(const ValueKey('queue-status-panel')),
        );
        expect(frame.bottom, lessThanOrEqualTo(panel.top));
        expect(tester.takeException(), isNull);
        queue.accept(
          'https://pulse.mirea.ru/lessons/visiting-logs/self-approve?token=abc',
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(queue.remaining, 0);
        expect(find.text('All confirmed'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        queue.dispose();
      },
    );
  }
}
