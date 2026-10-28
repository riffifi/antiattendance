import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'aa_id.dart';
import 'app_settings.dart';
import 'schedule_api.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

const _referencePrefix = 'server-session:';
String serverSessionReference(String id) => '$_referencePrefix$id';
String? serverAccountId(String value) =>
    value.startsWith(_referencePrefix) &&
        RegExp(r'^[a-f0-9-]{36}$')
            .hasMatch(value.substring(_referencePrefix.length))
    ? value.substring(_referencePrefix.length)
    : null;

const serverRpcPaths = {
  '/rtu_tc.rtu_attend.app.UserService/GetMeInfo': 'profile',
  '/rtu_tc.attendance.api.AttendanceService/SelfApproveAttendanceThroughQRCode':
      'attendance',
  '/rtu.pulse_app.LongTimeTokenService/GetAccessTokenForDigitalPass':
      'pass-token',
  '/rtu_tc.rtu_attend.humanpass.HumanPassService/SendVerificationCode':
      'pass-code',
  '/rtu_tc.rtu_attend.humanpass.HumanPassService/GetDigitalPass': 'pass-issue',
};

double? _expirySeconds(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? null : date.millisecondsSinceEpoch / 1000;
}

class SessionServerException implements Exception {
  const SessionServerException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class SessionServerClient {
  SessionServerClient(String address, {http.Client? client, this.groupId})
    : base = validateAddress(address),
      _http = client ?? http.Client();
  final Uri base;
  final http.Client _http;
  int? groupId;
  Map<String, dynamic> snapshot = {};

  /// When the server last answered; the pass is used only while it is recent.
  DateTime? fetchedAt;
  String? _passClientKey;
  Future<void>? _passClientLoading;
  String get _passClientStorageKey =>
      'pass_client_${sha256.convert(utf8.encode(base.origin))}';

  Future<void> restorePassIdentity() =>
      _passClientLoading ??= _restorePassIdentity();

  Future<void> _restorePassIdentity() async {
    final saved = await _testingStorage.read(key: _passClientStorageKey);
    if (saved != null && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(saved)) {
      _passClientKey = saved;
      return;
    }
    final random = Random.secure();
    final key = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    await _testingStorage.write(key: _passClientStorageKey, value: key);
    _passClientKey = key;
  }

  bool get requiresPassAgreements =>
      snapshot['pass_agreements_required'] == true;
  String? passAccessStatus(String id) =>
      accounts.where((a) => a['id'] == id).firstOrNull?['pass_access']
          as String?;
  DateTime? get passAccessUntil {
    final value = snapshot['pass_access_expires_at'];
    if (value is! num || !value.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round(),
      isUtc: true,
    );
  }

  Future<Uri> requestPassAccess(String id) async {
    await restorePassIdentity();
    final result = await _json(
      '/api/accounts/$id/pass-request',
      method: 'POST',
    );
    final url = Uri.tryParse(result['url'] as String? ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 't.me' ||
        url.userInfo.isNotEmpty ||
        url.port != 443) {
      throw const FormatException('Invalid Telegram bot link.');
    }
    return url;
  }

  String? _passTestKey;
  DateTime? _passTestUntil;
  Timer? _passTestTimer;
  static const _testingStorage = FlutterSecureStorage();
  String get _testingStorageKey =>
      'pass_testing_${sha256.convert(utf8.encode(base.origin))}';

  bool get passTestingActive =>
      _passTestKey != null &&
      (_passTestUntil?.isAfter(DateTime.now()) ?? false);
  DateTime? get passTestingUntil => passTestingActive ? _passTestUntil : null;
  Map<String, String> get _testHeaders => {
    if (passTestingActive) 'x-pass-test-key': _passTestKey!,
    'x-pass-client': ?_passClientKey,
  };

  Future<void> enablePassTesting(String password) async {
    final result = await _json(
      '/api/debug/pass-testing',
      method: 'POST',
      body: {'password': password},
    );
    final seconds = result['expires_at'];
    if (seconds is! num || !seconds.isFinite) {
      throw const FormatException('Invalid pass testing expiry.');
    }
    final until = DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).round(),
      isUtc: true,
    );
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero || remaining > const Duration(hours: 24)) {
      throw const FormatException('Invalid pass testing expiry.');
    }
    // The testing password lives in memory only; it is never written to the phone.
    _activatePassTesting(password, until);
  }

  void _activatePassTesting(String password, DateTime until) {
    _passTestKey = password.trim();
    _passTestUntil = until;
    _passTestTimer?.cancel();
    _passTestTimer = Timer(until.difference(DateTime.now()), () {
      unawaited(disablePassTesting());
      ServerSessions.notify();
      unawaited(ServerSessions.syncHandler?.call());
    });
  }

  /// Older versions saved the testing password; remove it instead of restoring.
  Future<void> restorePassTesting() async {
    if (await _testingStorage.read(key: _testingStorageKey) != null) {
      await _testingStorage.delete(key: _testingStorageKey);
    }
  }

  Future<void> disablePassTesting() async {
    _passTestTimer?.cancel();
    _passTestTimer = null;
    _passTestKey = null;
    _passTestUntil = null;
    snapshot = cacheSnapshot;
    await _testingStorage.delete(key: _testingStorageKey);
  }

  /// What may be written to the phone: account metadata only. Pass numbers and
  /// access leases stay in memory and come from the server on every start.
  Map<String, dynamic> get cacheSnapshot {
    if (snapshot.isEmpty) return {};
    return {
      ...snapshot,
      'pass_testing_expires_at': null,
      'pass_access_expires_at': null,
      'passes': [
        for (final row in snapshot['passes'] as List? ?? [])
          {...(row as Map).cast<String, dynamic>(), 'number': null},
      ],
    };
  }

  void setGroupFilter(int? id) {
    if (groupId == id) return;
    pause();
    groupId = id;
    snapshot = {};
  }

  String _groupQuery([bool hasQuery = false]) =>
      groupId == null ? '' : '${hasQuery ? '&' : '?'}group_id=$groupId';

  Future<List<ScheduleGroup>> groups() async {
    final result = await _json('/api/groups');
    return (result['groups'] as List).map((raw) {
      final row = raw as Map<String, dynamic>;
      return ScheduleGroup(
        id: row['id'] as int,
        name: row['name'] as String? ?? '${row['id']}',
      );
    }).toList();
  }

  Future<void> publishGroup(
    String id,
    int? group,
    String? name,
    int expectedVersion,
  ) async {
    await _json(
      '/api/accounts/$id/group',
      method: 'PUT',
      body: {
        'group_id': group,
        'group_name': name,
        'expected_version': expectedVersion,
      },
    );
  }

  final Map<String, String> importedIds = {};
  bool _closed = false;
  int _cursor = 0;
  int _watchGeneration = 0;
  bool _watching = false;
  static Uri validateAddress(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
        uri.hasQuery ||
        uri.hasFragment ||
        !{'', '/'}.contains(uri.path)) {
      throw const FormatException(
        'Use an HTTP(S) server address without paths or credentials.',
      );
    }
    return uri;
  }

  Uri _url(String path) => base.resolve(path);

  /// The AA ID bearer token every app API call carries. The server rejects
  /// calls without it once AA ID is enforced.
  Future<Map<String, String>> _aaIdHeaders() async {
    if (!AaId.signedIn) return const {};
    try {
      return {'authorization': 'Bearer ${await AaId.accessToken()}'};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _checkAaId(
    http.StreamedResponse response, {
    bool rpc = false,
  }) async {
    if (response.statusCode != 401 ||
        response.headers['x-aaid-required'] != '1') {
      return;
    }
    await response.stream.listen((_) {}).cancel();
    await AaId.rejected();
    if (rpc) {
      throw http.ClientException('Sign in to AA ID to use the session server.');
    }
    throw const SessionServerException(
      'Sign in to AA ID to use the session server.',
      status: 401,
    );
  }

  Future<Map<String, dynamic>> _json(
    String path, {
    String method = 'GET',
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = http.Request(method, _url(path))
      ..followRedirects = false
      ..headers.addAll({
        'content-type': 'application/json',
        ..._testHeaders,
        ...await _aaIdHeaders(),
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await _http.send(request).timeout(timeout);
    await _checkAaId(response);
    final bytes = BytesBuilder(copy: false);
    await for (final part in response.stream.timeout(timeout)) {
      if (part.length + bytes.length > 1024 * 1024) {
        throw const SessionServerException('Server response is too large.');
      }
      bytes.add(part);
    }
    if (response.statusCode != 200) {
      throw SessionServerException(
        'Session server returned HTTP ${response.statusCode}.',
        status: response.statusCode,
      );
    }
    final result = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Invalid session server response.');
    }
    return result;
  }

  Future<Map<String, dynamic>> fetch() async {
    await restorePassIdentity();
    final requestedGroup = groupId;
    final result = await _json('/api/accounts${_groupQuery()}');
    if (passTestingActive && result['pass_testing_expires_at'] == null) {
      await disablePassTesting();
      ServerSessions.notify();
    }
    if (groupId != requestedGroup) {
      throw StateError('Group changed during sync');
    }
    if (requestedGroup != null && result['group_filter'] != requestedGroup) {
      throw const FormatException(
        'Update the server to support group filtering.',
      );
    }
    if (result['protocol'] != 2 || result['sync'] != 'automatic') {
      throw const FormatException(
        'Update the server to support URL-only automatic synchronization.',
      );
    }
    if (result['accounts'] is! List ||
        result['passes'] is! List ||
        result['cursor'] is! int) {
      throw const FormatException('Invalid server account list.');
    }
    for (final record in result['accounts'] as List) {
      if (record is! Map<String, dynamic> ||
          record['id'] is! String ||
          serverAccountId(serverSessionReference(record['id'] as String)) ==
              null ||
          record['label'] is! String ||
          record['version'] is! int ||
          record['session_version'] is! int ||
          record['pass_version'] is! int) {
        throw const FormatException('Invalid server account.');
      }
      if (requestedGroup != null && record['group_id'] != requestedGroup) {
        throw const FormatException('The server returned a different group.');
      }
      // Cookies are never part of this protocol; reject a server exposing them.
      if (record.containsKey('cookie') || record.containsKey('secret')) {
        throw const FormatException('The server exposed session credentials.');
      }
    }
    final accountIds = (result['accounts'] as List).map((a) => a['id']).toSet();
    for (final record in result['passes'] as List) {
      if (record is! Map<String, dynamic> ||
          !accountIds.contains(record['account_id']) ||
          record['version'] is! int) {
        throw const FormatException('Invalid server pass record.');
      }
      final number = record['number'];
      if (number != null &&
          (number is! String ||
              !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(number) ||
              int.tryParse(number) == null)) {
        throw const FormatException('Invalid synchronized pass.');
      }
    }
    snapshot = result;
    fetchedAt = DateTime.now();
    if (identical(ServerSessions.active, this)) {
      await ServerSessions.saveSnapshot();
    }
    _cursor = result['cursor'] as int;
    return result;
  }

  List<Map<String, dynamic>> get accounts =>
      (snapshot['accounts'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((a) => groupId == null || a['group_id'] == groupId)
          .toList();
  String? passNumber(String id) {
    if (!canUsePass(id)) return null;
    for (final record in snapshot['passes'] as List? ?? []) {
      if (record is Map && record['account_id'] == id) {
        final value = record['number'];
        if (value == null) return null;
        if (value is! String ||
            int.tryParse(value) == null ||
            int.parse(value) <= 0) {
          throw const FormatException('Invalid synchronized pass.');
        }
        return value;
      }
    }
    return null;
  }

  /// The owner's switch on the server is absolute: without an explicit
  /// `pass_allowed: true` the pass is never used, testing included.
  bool canUsePass(String id) {
    final row = accounts.where((row) => row['id'] == id).firstOrNull;
    return row != null &&
        row['pass_allowed'] == true &&
        (passTestingActive ||
            !requiresPassAgreements ||
            (row['pass_access'] == 'approved' &&
                (passAccessUntil?.isAfter(DateTime.now()) ?? false)));
  }

  DateTime? testingExpiryFor(String id) {
    final row = accounts.where((a) => a['id'] == id).firstOrNull;
    if (row == null) return null;
    if (passTestingActive) return passTestingUntil;
    return requiresPassAgreements ? passAccessUntil : null;
  }

  int passVersion(String id) =>
      accounts.where((a) => a['id'] == id).firstOrNull?['pass_version']
          as int? ??
      0;
  Future<Map<String, dynamic>> publishSession(
    Map<String, dynamic> account, {
    String? remoteId,
    int? expectedSessionVersion,
  }) async {
    final result = await _json(
      '/api/accounts/import',
      method: 'POST',
      body: {
        'cookie': account['cookie'],
        'label': account['label'],
        'account_id': ?remoteId,
        'expected_session_version': ?expectedSessionVersion,
        'group_id': account['groupId'],
        'group_name': account['groupName'],
        'expires_at': account['expiresAt'] is String
            ? _expirySeconds(account['expiresAt'] as String)
            : null,
      },
    );
    final id = result['id'];
    if (id is! String || serverAccountId(serverSessionReference(id)) == null) {
      throw const FormatException('Invalid imported account.');
    }
    return result;
  }

  Future<void> publishExpiry(
    String id,
    DateTime expiry,
    int sessionVersion,
  ) async {
    await _json(
      '/api/accounts/$id/expiry',
      method: 'PUT',
      body: {
        'expires_at': expiry.millisecondsSinceEpoch / 1000,
        'expected_session_version': sessionVersion,
      },
    );
  }

  Future<void> publishPass(
    String id,
    String number, {
    required int expectedVersion,
  }) async {
    await _json(
      '/api/accounts/$id/pass',
      method: 'PUT',
      body: {'number': number, 'expected_version': expectedVersion},
    );
  }

  Future<http.StreamedResponse> proxy(
    String id,
    String method,
    List<int> body, {
    String? pulseToken,
    http.Client? transport,
  }) async {
    if (!serverRpcPaths.containsValue(method)) {
      throw http.ClientException('RPC is not allowed.');
    }
    final request = http.Request('POST', _url('/api/accounts/$id/rpc/$method'))
      ..followRedirects = false
      ..headers.addAll({
        'content-type': 'application/grpc-web+proto',
        'x-pulse-token': ?pulseToken,
        ..._testHeaders,
        ...await _aaIdHeaders(),
      })
      ..bodyBytes = body;
    final response = await (transport ?? _http)
        .send(request)
        .timeout(const Duration(seconds: 20));
    await _checkAaId(response, rpc: true);
    if (response.headers['x-pass-test-invalid'] == '1') {
      await disablePassTesting();
      ServerSessions.notify();
    }
    if (response.statusCode == 401) {
      await response.stream.listen((_) {}).cancel();
      throw http.ClientException(
        'The server requires HTTP authentication. Check its Nginx configuration.',
      );
    }
    return response;
  }

  void watch() {
    if (_watching || _closed) return;
    _watching = true;
    final generation = ++_watchGeneration;
    unawaited(_watch(generation));
  }

  void pause() {
    _watching = false;
    ++_watchGeneration;
  }

  Future<void> _watch(int generation) async {
    while (!_closed && generation == _watchGeneration) {
      try {
        final result = await _json(
          '/api/events?after=$_cursor&wait=25${_groupQuery(true)}',
          timeout: const Duration(seconds: 35),
        );
        if (_closed || generation != _watchGeneration) return;
        final events = result['events'];
        final cursor = result['cursor'];
        if (cursor is! int || events is! List) {
          throw const FormatException('Invalid update event.');
        }
        _cursor = cursor;
        if (events.isNotEmpty) {
          await fetch();
          ServerSessions.notify();
        }
        await ServerSessions.syncHandler?.call();
      } catch (_) {
        await ServerSessions.syncHandler?.call();
        if (_closed || generation != _watchGeneration) return;
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  void close() {
    _passTestTimer?.cancel();
    _passTestKey = null;
    _closed = true;
    pause();
    _http.close();
  }
}

class ServerRpcClient extends http.BaseClient {
  ServerRpcClient(this.server, this.accountId, {http.Client? transport})
    : _transport = transport ?? http.Client();
  final SessionServerClient server;
  final String accountId;
  final http.Client _transport;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final method = serverRpcPaths[request.url.path];
    if (request.method != 'POST' ||
        request.url.scheme != 'https' ||
        request.url.host != 'pulse.mirea.ru' ||
        method == null) {
      throw http.ClientException(
        'Only supported Pulse RPCs can use the server.',
      );
    }
    final body = await request.finalize().toBytes();
    final auth = request.headers['authorization'];
    return server.proxy(
      accountId,
      method,
      body,
      transport: _transport,
      pulseToken: auth?.startsWith('Bearer ') == true
          ? auth!.substring(7)
          : null,
    );
  }

  @override
  void close() => _transport.close();
}

abstract final class ServerSessions {
  static const _storage = FlutterSecureStorage();
  static SessionServerClient? active;
  static Future<void> Function()? syncHandler;
  static final _changes = StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;
  static void notify() {
    _changes.add(null);
  }

  static Future<void> initialize() async {
    if (active != null) return;
    final config = await _storage.read(key: 'session_server_config_v1');
    if (config == null) return;
    final data = jsonDecode(config) as Map<String, dynamic>;
    active = SessionServerClient(
      data['url'] as String,
      groupId: (await AppSettingsStore().loadMyGroup())?.id,
    );
    // Migrate old URL/key configurations without keeping a device credential.
    if (data.containsKey('key')) {
      await _storage.write(
        key: 'session_server_config_v1',
        value: jsonEncode({'url': data['url']}),
      );
    }
    final cached = await _storage.read(key: 'session_server_snapshot_v1');
    if (cached != null) {
      active!.snapshot = jsonDecode(cached) as Map<String, dynamic>;
      // Older versions could have cached pass numbers; keep metadata only.
      active!.snapshot = active!.cacheSnapshot;
      await saveSnapshot();
    }
    await active!.restorePassIdentity();
    await active!.restorePassTesting();
    final mappings = await _storage.read(key: 'session_server_mappings_v1');
    if (mappings != null) {
      active!.importedIds.addAll(
        (jsonDecode(mappings) as Map<String, dynamic>).cast<String, String>(),
      );
    }
  }

  static Future<void> connect(SessionServerClient client) async {
    client.setGroupFilter((await AppSettingsStore().loadMyGroup())?.id);
    await client.restorePassIdentity();
    await client.restorePassTesting();
    await client.fetch();
    await _storage.write(
      key: 'session_server_config_v1',
      value: jsonEncode({'url': client.base.toString()}),
    );
    final previous = active;
    final sameServer = previous?.base.origin == client.base.origin;
    if (sameServer) client.importedIds.addAll(previous!.importedIds);
    previous?.close();
    active = client;
    await saveSnapshot();
    if (sameServer) {
      await saveMappings();
    } else {
      await _storage.delete(key: 'session_server_mappings_v1');
    }
    await syncHandler?.call();
    client.watch();
    notify();
  }

  static Future<void> disconnect() async {
    active?.close();
    active = null;
    await _storage.delete(key: 'session_server_config_v1');
    await _storage.delete(key: 'session_server_snapshot_v1');
    await _storage.delete(key: 'session_server_mappings_v1');
    notify();
  }

  static Future<void> saveSnapshot() => _storage.write(
    key: 'session_server_snapshot_v1',
    value: jsonEncode(active?.cacheSnapshot ?? {}),
  );

  static Future<void> saveMappings() => _storage.write(
    key: 'session_server_mappings_v1',
    value: jsonEncode(active?.importedIds ?? {}),
  );
  static SessionServerClient requireClient() {
    final client = active;
    if (client == null) {
      throw http.ClientException('Connect to the session server in Settings.');
    }
    return client;
  }
}
