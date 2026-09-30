import 'dart:typed_data';

import 'package:antiattendance/pulse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<int> frame(List<int> message) => [
  0,
  0,
  0,
  0,
  message.length,
  ...message,
  0x80,
  0,
  0,
  0,
  16,
  ...'grpc-status: 0\r\n'.codeUnits,
];

void main() {
  test('accepts only a Pulse attendance token', () {
    expect(
      attendanceTokenFromQr(
        'https://pulse.mirea.ru/lessons/visiting-logs/self-approve?token=abc',
      ),
      'abc',
    );
    expect(
      () => attendanceTokenFromQr('https://evil.example/?token=abc'),
      throwsFormatException,
    );
    expect(
      () => attendanceTokenFromQr('https://pulse.mirea.ru/?token=a&token=b'),
      throwsFormatException,
    );
  });

  test('validates a chunked Pulse session', () {
    expect(
      pulseSessionCookie({
        '.AspNetCore.Cookies': 'chunks-1',
        '.AspNetCore.CookiesC1': 'abc',
      }),
      '.AspNetCore.Cookies=chunks-1; .AspNetCore.CookiesC1=abc',
    );
    expect(
      () => pulseSessionCookie({'.AspNetCore.Cookies': 'chunks-2'}),
      throwsFormatException,
    );
  });

  test(
    'sends protobuf token with separate session and decodes approval',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.path,
          '/rtu_tc.attendance.api.AttendanceService/SelfApproveAttendanceThroughQRCode',
        );
        expect(request.headers['cookie'], '.AspNetCore.Cookies=session');
        expect(request.bodyBytes.sublist(5), [10, 3, 97, 98, 99]);
        // approved { lessonId: "id" }
        return http.Response.bytes(frame([18, 4, 10, 2, 105, 100]), 200);
      });
      final api = PulseApi(client: client);
      final result = await api.approve('abc', '.AspNetCore.Cookies=session');
      expect(result.state, ApprovalState.approved);
      expect(result.lessonId, 'id');
      api.close();
    },
  );

  test('reports the campus-presence restriction', () {
    final result = decodeApproval(Uint8List.fromList([10, 2, 8, 5]));
    expect(result.state, ApprovalState.rejected);
    expect(result.message, contains('кампусе'));
  });

  test('treats a login redirect as an expired session', () async {
    final client = MockClient((request) async {
      expect(request.followRedirects, isFalse);
      return http.Response('', 302, headers: {'location': '/api/auth/login'});
    });
    final api = PulseApi(client: client);
    await expectLater(
      api.approve('abc', '.AspNetCore.Cookies=expired'),
      throwsA(
        isA<PulseApiException>().having(
          (error) => error.message,
          'message',
          contains('Сессия истекла'),
        ),
      ),
    );
    api.close();
  });
}
