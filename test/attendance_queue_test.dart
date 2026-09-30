import 'dart:async';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/attendance_queue.dart';
import 'package:antiattendance/pulse_api.dart';
import 'package:flutter_test/flutter_test.dart';

String qr(String token) => 'https://pulse.mirea.ru/lesson?token=$token';

void main() {
  test('retries only accounts without confirmation on the next QR', () async {
    final calls = <String>[];
    final queue = AttendanceQueue(
      accounts: const [
        SavedAccount(id: 'a', label: 'A', cookie: 'a'),
        SavedAccount(id: 'b', label: 'B', cookie: 'b'),
      ],
      approve: (account, token) async {
        calls.add('${account.id}:$token');
        return ApprovalResult(
          account.id == 'a' || token == 'second'
              ? ApprovalState.approved
              : ApprovalState.waiting,
          'result',
        );
      },
    );

    queue.accept(qr('first'));
    await pumpEventQueue();
    expect(queue.remaining, 1);
    queue.accept(qr('first')); // Repeated camera frame is ignored.
    queue.accept(qr('second'));
    await pumpEventQueue();
    expect(calls, ['a:first', 'b:first', 'b:second']);
    expect(queue.remaining, 0);
    queue.accept(qr('third'));
    expect(calls.length, 3);
    queue.dispose();
  });

  test('keeps latest QR while requests are in flight', () async {
    final first = Completer<ApprovalResult>();
    final calls = <String>[];
    final queue = AttendanceQueue(
      accounts: const [SavedAccount(id: 'a', label: 'A', cookie: 'a')],
      approve: (account, token) {
        calls.add(token);
        if (token == 'first') return first.future;
        return Future.value(
          const ApprovalResult(ApprovalState.approved, 'confirmed'),
        );
      },
    );

    queue.accept(qr('first'));
    queue.accept(qr('second'));
    queue.accept(qr('third'));
    first.complete(const ApprovalResult(ApprovalState.waiting, 'waiting'));
    await pumpEventQueue();
    expect(calls, ['first', 'third']);
    expect(queue.remaining, 0);
    queue.dispose();
  });
}
