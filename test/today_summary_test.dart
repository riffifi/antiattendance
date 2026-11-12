import 'package:antiattendance/today_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts only the person’s classes and never turns missing cells into absence', () {
    final summary = TodayPersonSummary(
      {'id': 'alice', 'group_id': 1},
      [
        {
          'groups': [
            {'id': 1},
          ],
          'state': 'past',
          'marks': {
            'alice': {'state': 'approved'},
          },
        },
        {
          'groups': [
            {'id': 2},
          ],
          'state': 'past',
        },
        {
          'groups': [
            {'id': 1},
          ],
          'state': 'past',
          'marks': {
            'bob': {'state': 'approved'},
          },
        },
        {
          'groups': [
            {'id': 1},
          ],
          'state': 'future',
        },
      ],
    );
    expect(summary.lessons.length, 3);
    expect(summary.confirmations, 1);
    expect(summary.unresolved, 1);
    expect(summary.mark(summary.lessons[1]), isNull);
    expect(summary.needsAttention, isTrue);
  });
  test(
    'future lessons alone do not require attention, expired sessions do',
    () {
      final lessons = <Map<String, dynamic>>[
        {'state': 'future'},
      ];
      expect(
        TodayPersonSummary({
          'id': 'a',
          'session': 'valid',
        }, lessons).needsAttention,
        isFalse,
      );
      expect(
        TodayPersonSummary({
          'id': 'a',
          'session': 'expired',
        }, lessons).needsAttention,
        isTrue,
      );
    },
  );
  test(
    'legacy Pulse presence and normalized person/group search remain supported',
    () {
      final summary = TodayPersonSummary(
        {
          'id': 'a',
          'label': 'Alex Morgan',
          'username': 'alex',
          'group_name': 'Group A',
        },
        [
          {
            'mirea': {'a': 'present'},
            'state': 'past',
          },
        ],
      );
      expect(summary.confirmations, 1);
      expect(summary.needsAttention, isFalse);
      expect(summary.matches(' GROUP A '), isTrue);
      expect(summary.matches('morgan'), isTrue);
      expect(summary.matches('sam'), isFalse);
    },
  );
}
