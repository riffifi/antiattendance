import 'server_sessions.dart';

List<Map<String, dynamic>> serverRows(Object? value) => value is List
    ? value.whereType<Map>().map((v) => v.cast<String, dynamic>()).toList()
    : const [];
Map<String, dynamic> serverObject(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

/// Shared website/app JSON operations. Mutations are never automatically
/// retried: a lost attendance response may already have marked people.
class AaServerApi {
  AaServerApi(this.client);
  final SessionServerClient client;
  Future<Map<String, dynamic>> state({int? lessonStart}) => client.requestJson(
    '/site/state${lessonStart == null ? '' : '?lesson_start=$lessonStart'}',
  );
  Future<Map<String, dynamic>> today() => client.requestJson('/site/today');
  Future<Map<String, dynamic>> schedule({
    int week = 0,
    int? group,
  }) => client.requestJson(
    '/site/schedule?week=${week.clamp(-30, 30)}${group == null ? '' : '&group=$group'}',
  );
  Future<Map<String, dynamic>> searchGroups(String query) => client.requestJson(
    '/site/schedule/search?q=${Uri.encodeQueryComponent(query.trim())}',
  );
  Future<List<Map<String, dynamic>>> mark(
    String qr,
    Iterable<String> ids, {
    int? lessonStart,
  }) async {
    final selected = ids.toSet().toList();
    if (selected.isEmpty || selected.length > 200) {
      throw ArgumentError('Choose between 1 and 200 people.');
    }
    final result = await client.requestJson(
      '/site/mark',
      method: 'POST',
      body: {
        'qr': qr,
        'account_ids': selected,
        'own_group': false,
        'lesson_start': ?lessonStart,
      },
    );
    if (result['results'] is! List) {
      throw const FormatException('Invalid attendance result.');
    }
    return serverRows(result['results']);
  }

  Future<Map<String, dynamic>> myPass() => client.requestJson('/api/me/pass');
  Future<Map<String, dynamic>> passes() => client.requestJson('/api/me/passes');
  Future<Map<String, dynamic>> digitalPasses() =>
      client.requestJson('/site/passes');
  Future<Map<String, dynamic>> digitalPass(String id) =>
      client.requestJson('/site/passes/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> sendPassCode({String? accountId}) =>
      client.requestJson(
        accountId == null
            ? '/site/pass/code'
            : '/site/passes/${Uri.encodeComponent(accountId)}/code',
        method: 'POST',
        timeout: const Duration(seconds: 35),
      );
  Future<Map<String, dynamic>> issuePass(String code, {String? accountId}) {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const FormatException('Enter a six-digit verification code.');
    }
    return client.requestJson(
      accountId == null
          ? '/site/pass/issue'
          : '/site/passes/${Uri.encodeComponent(accountId)}/issue',
      method: 'POST',
      body: {'code': code},
      timeout: const Duration(seconds: 35),
    );
  }

  Future<Map<String, dynamic>> people(String username) => client.requestJson(
    '/api/me/people?q=${Uri.encodeQueryComponent(username.trim())}',
  );
  Future<Map<String, dynamic>> account() =>
      client.requestJson('/api/me/account');
  Future<Map<String, dynamic>> updateAccount({
    String? label,
    bool? passAllowed,
  }) => client.requestJson(
    '/api/me/account',
    method: 'PUT',
    body: {'label': ?label, 'pass_allowed': ?passAllowed},
  );
  Future<Map<String, dynamic>> grant(String id) => client.requestJson(
    '/api/me/pass/people',
    method: 'POST',
    body: {'account_id': id},
  );
  Future<Map<String, dynamic>> requestPass(String id) => client.requestJson(
    '/api/me/pass/requests',
    method: 'POST',
    body: {'account_id': id},
  );
  Future<Map<String, dynamic>> revoke(String id) => client.requestJson(
    '/api/me/pass/people/aaid/${Uri.encodeComponent(id)}',
    method: 'DELETE',
  );
  Future<Map<String, dynamic>> decide(
    String id,
    bool allow,
  ) => client.requestJson(
    '/api/me/pass/requests/${Uri.encodeComponent(id)}/${allow ? 'allow' : 'deny'}',
    method: 'POST',
  );
}

/// A missing cell never becomes an absence or a mark in a neighboring lesson.
Map<String, dynamic>? dayMark(Map<String, dynamic> lesson, String accountId) {
  final value =
      serverObject(lesson['marks'])[accountId] ??
      serverObject(lesson['mirea'])[accountId];
  if (value is Map) return value.cast<String, dynamic>();
  if (value is String && value.isNotEmpty) {
    return {'state': value == 'present' ? 'approved' : value, 'message': value};
  }
  return null;
}
