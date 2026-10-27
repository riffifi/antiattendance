import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// AA ID runs next to the session server, behind its Nginx at `/id`.
const defaultAaIdUrl = 'https://aa.yellowteacrew.ru/id';

class AaIdException implements Exception {
  const AaIdException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class AaIdSession {
  const AaIdSession({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.sessionId,
    required this.userId,
    this.groupId,
    this.groupName,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final String sessionId;
  final String userId;
  final int? groupId;
  final String? groupName;

  factory AaIdSession.fromServer(Map<String, dynamic> data) {
    final user = data['user'];
    final expires = data['access_expires_at'];
    if (data['access_token'] is! String ||
        data['refresh_token'] is! String ||
        data['session_id'] is! String ||
        expires is! num ||
        user is! Map<String, dynamic> ||
        user['id'] is! String) {
      throw const FormatException('Invalid AA ID response.');
    }
    return AaIdSession(
      accessToken: data['access_token'] as String,
      accessExpiresAt: DateTime.fromMillisecondsSinceEpoch(
        (expires * 1000).round(),
        isUtc: true,
      ),
      refreshToken: data['refresh_token'] as String,
      sessionId: data['session_id'] as String,
      userId: user['id'] as String,
      groupId: user['group_id'] is int ? user['group_id'] as int : null,
      groupName: user['group_name'] is String
          ? user['group_name'] as String
          : null,
    );
  }

  Map<String, dynamic> toServerJson() => {
    'access_token': accessToken,
    'access_expires_at': accessExpiresAt.millisecondsSinceEpoch / 1000,
    'refresh_token': refreshToken,
    'session_id': sessionId,
    'user': {'id': userId, 'group_id': groupId, 'group_name': groupName},
  };
}

class AaIdDevice {
  const AaIdDevice({
    required this.id,
    required this.device,
    required this.lastUsed,
    required this.current,
  });
  final String id;
  final String device;
  final DateTime lastUsed;
  final bool current;
}

class AaIdClient {
  AaIdClient(String address, {http.Client? client})
    : base = validateAddress(address),
      _http = client ?? http.Client();
  final Uri base;
  final http.Client _http;

  /// AA ID may live under a path (`https://host/id`), unlike the session server.
  static Uri validateAddress(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Use an HTTP(S) AA ID address.');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  Future<Map<String, dynamic>> _json(
    String path, {
    String method = 'GET',
    Object? body,
    String? accessToken,
  }) async {
    final request = http.Request(method, base.resolve(path))
      ..followRedirects = false
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': ?(accessToken == null ? null : 'Bearer $accessToken'),
      });
    if (body != null) request.body = jsonEncode(body);
    const timeout = Duration(seconds: 20);
    final response = await _http.send(request).timeout(timeout);
    final bytes = BytesBuilder(copy: false);
    await for (final part in response.stream.timeout(timeout)) {
      if (part.length + bytes.length > 256 * 1024) {
        throw const AaIdException('AA ID response is too large.');
      }
      bytes.add(part);
    }
    if (response.statusCode != 200) {
      throw AaIdException(
        'AA ID returned HTTP ${response.statusCode}.',
        status: response.statusCode,
      );
    }
    final result = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Invalid AA ID response.');
    }
    return result;
  }

  /// Proves MIREA ownership with a fresh Pulse session. AA ID asks Pulse who the
  /// session belongs to and drops the cookie; it is never stored there.
  Future<AaIdSession> signInWithPulse(String cookie, {String? device}) async =>
      AaIdSession.fromServer(
        await _json(
          'v1/auth/mirea',
          method: 'POST',
          body: {'pulse_cookie': cookie, 'device': device ?? deviceName()},
        ),
      );

  Future<AaIdSession> refresh(String refreshToken) async =>
      AaIdSession.fromServer(
        await _json(
          'v1/auth/refresh',
          method: 'POST',
          body: {'refresh_token': refreshToken},
        ),
      );

  Future<void> logout(String accessToken) =>
      _json('v1/auth/logout', method: 'POST', accessToken: accessToken);

  Future<List<AaIdDevice>> devices(String accessToken) async {
    final result = await _json('v1/me/sessions', accessToken: accessToken);
    final rows = result['sessions'];
    if (rows is! List) throw const FormatException('Invalid AA ID response.');
    return [
      for (final row in rows)
        if (row is Map<String, dynamic> &&
            row['id'] is String &&
            row['last_used'] is num)
          AaIdDevice(
            id: row['id'] as String,
            device: row['device'] as String? ?? '',
            lastUsed: DateTime.fromMillisecondsSinceEpoch(
              ((row['last_used'] as num) * 1000).round(),
            ),
            current: row['current'] == true,
          ),
    ];
  }

  Future<void> revoke(String accessToken, String sessionId) => _json(
    'v1/me/sessions/${Uri.encodeComponent(sessionId)}',
    method: 'DELETE',
    accessToken: accessToken,
  );

  void close() => _http.close();

  static String deviceName() {
    try {
      return switch (Platform.operatingSystem) {
        'android' => 'Android',
        'ios' => 'iPhone',
        final other => other,
      };
    } catch (_) {
      return 'Phone';
    }
  }
}

/// The signed-in AA ID of this phone. Nothing else in the app works without it.
abstract final class AaId {
  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'aa_id_session_v1';
  static const _urlKey = 'aa_id_url_v1';
  static AaIdSession? session;
  static String url = defaultAaIdUrl;
  static http.Client Function() httpClient = http.Client.new;
  static Future<void>? _loading;
  static Future<String>? _refreshing;
  static final _changes = StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;
  static bool get signedIn => session != null;

  static Future<void> initialize() => _loading ??= _restore();

  static Future<void> _restore() async {
    url = await _storage.read(key: _urlKey) ?? defaultAaIdUrl;
    final saved = await _storage.read(key: _sessionKey);
    if (saved == null) return;
    try {
      session = AaIdSession.fromServer(
        jsonDecode(saved) as Map<String, dynamic>,
      );
    } catch (_) {
      await _storage.delete(key: _sessionKey);
    }
  }

  static AaIdClient client([String? address]) =>
      AaIdClient(address ?? url, client: httpClient());

  static Future<void> signIn(String address, String pulseCookie) async {
    final api = client(address);
    try {
      final result = await api.signInWithPulse(pulseCookie);
      url = api.base.toString();
      await _storage.write(key: _urlKey, value: url);
      await _save(result);
    } finally {
      api.close();
    }
  }

  static Future<void> _save(AaIdSession value) async {
    session = value;
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode(value.toServerJson()),
    );
    _changes.add(null);
  }

  /// A valid access token, refreshed shortly before it expires. Throws
  /// [AaIdException] with status 401 after the session ends elsewhere (device
  /// limit, revocation, a copied refresh token); the app then asks to sign in.
  static Future<String> accessToken() async {
    await initialize();
    final current = session;
    if (current == null) {
      throw const AaIdException('Sign in to AA ID.', status: 401);
    }
    if (current.accessExpiresAt.isAfter(
      DateTime.now().add(const Duration(seconds: 60)),
    )) {
      return current.accessToken;
    }
    return _refreshing ??= _refresh(current)
        .whenComplete(() => _refreshing = null);
  }

  static Future<String> _refresh(AaIdSession current) async {
    final api = client();
    try {
      final next = await api.refresh(current.refreshToken);
      await _save(next);
      return next.accessToken;
    } on AaIdException catch (error) {
      if (error.status == 401 || error.status == 403) {
        await _forget();
      }
      rethrow;
    } finally {
      api.close();
    }
  }

  /// Called when a service rejects the token as no longer valid.
  static Future<void> rejected() async {
    final current = session;
    if (current == null) return;
    // An access token can be rejected after revocation; refreshing tells which.
    try {
      await _refresh(current);
    } catch (_) {
      // _refresh signs out on a definitive rejection.
    }
  }

  static Future<List<AaIdDevice>> devices() async {
    final token = await accessToken();
    final api = client();
    try {
      return await api.devices(token);
    } finally {
      api.close();
    }
  }

  static Future<void> revoke(String sessionId) async {
    final token = await accessToken();
    final api = client();
    try {
      await api.revoke(token, sessionId);
    } finally {
      api.close();
    }
  }

  static Future<void> signOut() async {
    final current = session;
    if (current != null) {
      final api = client();
      try {
        await api.logout(current.accessToken);
      } catch (_) {
        // Signing out locally must work offline too.
      } finally {
        api.close();
      }
    }
    await _forget();
  }

  static Future<void> _forget() async {
    session = null;
    await _storage.delete(key: _sessionKey);
    _changes.add(null);
  }

  /// Test hook.
  static void reset() {
    session = null;
    url = defaultAaIdUrl;
    _loading = null;
    _refreshing = null;
    httpClient = http.Client.new;
  }
}
