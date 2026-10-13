import 'package:flutter_test/flutter_test.dart';

import 'package:antiattendance/acs_entry_rules.dart';
import 'package:antiattendance/acs_timeline.dart';

void main() {
  test('matches the S20 central entrance transition', () {
    const matcher = AcsEntryMatcher([
      AcsEntryRule(
        fromName: 'Неконтролируемая территория',
        toName: 'С20 1эт ЦентральныйВход',
      ),
    ]);
    const event = AcsEvent(
      id: 'event',
      at: DateTime.utc(2026, 10, 13, 12, 28),
      fromId: 'source',
      fromName: 'Неконтролируемая территория',
      toId: 's20',
      toName: 'С20 1эт ЦентральныйВход',
    );

    expect(matcher.matches(event), isTrue);
  });

  test('does not accept an unconfigured source', () {
    const matcher = AcsEntryMatcher([
      AcsEntryRule(
        fromName: 'Неконтролируемая территория',
        toName: 'С20 1эт ЦентральныйВход',
      ),
    ]);
    const event = AcsEvent(
      id: 'event',
      at: DateTime.utc(2026, 10, 13, 12, 28),
      fromId: 'source',
      fromName: 'Неконтролируемая территория',
      toId: 'building-a',
      toName: 'Entrance',
    );

    expect(matcher.matches(event), isFalse);
  });

  test('classifies the latest configured transition', () {
    const matcher = AcsPresenceMatcher(
      entryMatcher: AcsEntryMatcher([
        AcsEntryRule(
          fromName: 'Неконтролируемая территория',
          toName: 'С20 1эт ЦентральныйВход',
        ),
      ]),
      exitMatcher: AcsEntryMatcher([
        AcsEntryRule(
          fromName: 'С20 1эт ЦентральныйВход',
          toName: 'Неконтролируемая территория',
        ),
      ]),
    );
    const entry = AcsEvent(
      id: 'entry',
      at: DateTime.utc(2026, 10, 13, 12, 28),
      fromId: 'outside',
      fromName: 'Неконтролируемая территория',
      toId: 's20',
      toName: 'С20 1эт ЦентральныйВход',
    );
    const exit = AcsEvent(
      id: 'exit',
      at: DateTime.utc(2026, 10, 13, 14, 13),
      fromId: 's20',
      fromName: 'С20 1эт ЦентральныйВход',
      toId: 'outside',
      toName: 'Неконтролируемая территория',
    );

    expect(matcher.classify([entry]), AcsPresence.inside);
    expect(matcher.classify([entry, exit]), AcsPresence.outside);
  });
}
