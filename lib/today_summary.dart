import 'server_api.dart';

/// Results stay scoped to the person's classes. Missing cells are unknown.
class TodayPersonSummary {
  TodayPersonSummary(this.person, List<Map<String, dynamic>> allLessons)
    : lessons = allLessons.where((lesson) {
        final groups = serverRows(lesson['groups']);
        final group = person['group_id'];
        return groups.isEmpty ||
            group == null ||
            groups.any((g) => '${g['id']}' == '$group');
      }).toList();

  final Map<String, dynamic> person;
  final List<Map<String, dynamic>> lessons;
  String get id => '${person['id']}';
  String get name => '${person['label'] ?? person['username'] ?? '—'}';
  Map<String, dynamic>? mark(Map<String, dynamic> lesson) =>
      dayMark(lesson, id);
  bool confirmed(Map<String, dynamic> lesson) =>
      ['approved', 'present'].contains(mark(lesson)?['state']);
  int get confirmations => lessons.where(confirmed).length;
  int get unresolved => lessons
      .where((lesson) => lesson['state'] != 'future' && !confirmed(lesson))
      .length;
  bool get signInNeeded => [
    'expired',
    'invalid',
    'missing',
    'reauth_required',
  ].contains(person['session']);
  bool get needsAttention => signInNeeded || unresolved > 0;
  bool matches(String query) =>
      '$name ${person['username'] ?? ''} ${person['group_name'] ?? ''}'
          .toLowerCase()
          .contains(query.trim().toLowerCase());
}
