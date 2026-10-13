import 'acs_timeline.dart';

class AcsEntryRule {
  const AcsEntryRule({
    this.fromId,
    this.fromName,
    this.toId,
    this.toName,
  });

  final String? fromId;
  final String? fromName;
  final String? toId;
  final String? toName;

  bool matches(AcsEvent event) =>
      (fromId == null || event.fromId == fromId) &&
      (fromName == null || event.fromName == fromName) &&
      (toId == null || event.toId == toId) &&
      (toName == null || event.toName == toName);
}

class AcsEntryMatcher {
  const AcsEntryMatcher(this.rules);

  final List<AcsEntryRule> rules;

  bool matches(AcsEvent event) => rules.any((rule) => rule.matches(event));
}

enum AcsPresence { inside, outside, unknown }

class AcsPresenceMatcher {
  const AcsPresenceMatcher({
    required this.entryMatcher,
    required this.exitMatcher,
  });

  final AcsEntryMatcher entryMatcher;
  final AcsEntryMatcher exitMatcher;

  AcsPresence classify(Iterable<AcsEvent> events) {
    final ordered = events.toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    for (final event in ordered.reversed) {
      if (entryMatcher.matches(event)) return AcsPresence.inside;
      if (exitMatcher.matches(event)) return AcsPresence.outside;
    }
    return AcsPresence.unknown;
  }
}

// Add another rule here when a campus uses a different entrance location.
const acsEntryMatcher = AcsEntryMatcher([
  AcsEntryRule(
    fromName: 'Неконтролируемая территория',
    toName: 'С20 1эт ЦентральныйВход',
  ),
  AcsEntryRule(
    fromName: 'Неконтролируемая территория',
    toName: 'В78 А 2эт ЦентральныйВход',
  ),
]);

const acsPresenceMatcher = AcsPresenceMatcher(
  entryMatcher: acsEntryMatcher,
  exitMatcher: AcsEntryMatcher([
    AcsEntryRule(
      fromName: 'С20 1эт ЦентральныйВход',
      toName: 'Неконтролируемая территория',
    ),
    AcsEntryRule(
      fromName: 'В78 А 2эт ЦентральныйВход',
      toName: 'Неконтролируемая территория',
    ),
  ]),
);
