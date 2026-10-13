import 'server_sessions.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nfc_pass_client/nfc_pass_client.dart'
    show nfcSessionCookieHeader;

import 'pulse_api.dart' show pulseHost;

const pulseProfilePath = '/rtu_tc.rtu_attend.app.UserService/GetMeInfo';
const pulseProfileUrl = 'https://pulse.mirea.ru$pulseProfilePath';

enum PulseSessionState {
  valid,
  expired,
  forbidden,
  unavailable,
  invalidResponse,
}

/// Read-only identity check used by the current Pulse frontend. It neither
/// enrolls a digital pass nor changes attendance, and does not depend on either.
Future<PulseSessionState> probePulseSession(
  String cookie, {
  http.Client? client,
}) async {
  final owned = client == null;
  final remoteId = serverAccountId(cookie);
  http.Client? transport;
  try {
    transport =
        client ??
        (remoteId == null
            ? http.Client()
            : ServerRpcClient(ServerSessions.requireClient(), remoteId));
    final origin = utf8.encode('https://$pulseHost');
    final payload = <int>[10, origin.length, ...origin, 24, 1];
    final request = http.Request('POST', Uri.parse(pulseProfileUrl))
      ..followRedirects = false
      ..headers.addAll({
        'content-type': 'application/grpc-web+proto',
        'accept': 'application/grpc-web+proto',
        'x-grpc-web': '1',
        'x-requested-with': 'XMLHttpRequest',
        'origin': 'https://$pulseHost',
        'referer': 'https://$pulseHost/services',
        if (remoteId == null) 'cookie': nfcSessionCookieHeader(cookie),
      })
      ..bodyBytes = (Uint8List(5 + payload.length)
        ..buffer.asByteData().setUint32(1, payload.length)
        ..setRange(5, 5 + payload.length, payload));
    final response = await transport
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      if (response.statusCode == 401) return PulseSessionState.expired;
      if (response.statusCode == 403) return PulseSessionState.forbidden;
      final location = Uri.tryParse(response.headers['location'] ?? '');
      if ({301, 302, 303, 307, 308}.contains(response.statusCode) &&
          location != null &&
          (location.path.contains('/auth/login') ||
              location.host == 'sso.mirea.ru')) {
        return PulseSessionState.expired;
      }
      return PulseSessionState.unavailable;
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      if (body.length + chunk.length > 1024 * 1024) {
        return PulseSessionState.invalidResponse;
      }
      body.add(chunk);
    }
    if (!(response.headers['content-type'] ?? '').toLowerCase().startsWith(
      'application/grpc-web',
    )) {
      return PulseSessionState.invalidResponse;
    }
    return decodePulseSession(
      body.takeBytes(),
      grpcStatus: response.headers['grpc-status'],
    );
  } on FormatException {
    return PulseSessionState.invalidResponse;
  } on http.ClientException {
    return PulseSessionState.unavailable;
  } on TimeoutException {
    return PulseSessionState.unavailable;
  } catch (_) {
    return PulseSessionState.unavailable;
  } finally {
    if (owned) transport?.close();
  }
}

PulseSessionState decodePulseSession(Uint8List bytes, {String? grpcStatus}) {
  try {
    Uint8List? message;
    var offset = 0;
    while (offset < bytes.length) {
      if (bytes.length - offset < 5) {
        throw const FormatException('Truncated gRPC frame');
      }
      final flag = bytes[offset];
      final size = ByteData.sublistView(
        bytes,
        offset + 1,
        offset + 5,
      ).getUint32(0);
      offset += 5;
      if (size > bytes.length - offset) {
        throw const FormatException('Truncated gRPC body');
      }
      final part = Uint8List.sublistView(bytes, offset, offset + size);
      offset += size;
      if (flag == 0) {
        if (message != null) {
          throw const FormatException('Multiple unary messages');
        }
        message = part;
      } else if (flag == 0x80) {
        for (final line in ascii.decode(part).split('\r\n')) {
          final colon = line.indexOf(':');
          if (colon > 0 &&
              line.substring(0, colon).trim().toLowerCase() == 'grpc-status') {
            final status = line.substring(colon + 1).trim();
            if (grpcStatus != null && status != grpcStatus) {
              throw const FormatException('Conflicting gRPC status');
            }
            grpcStatus = status;
          }
        }
      } else {
        throw const FormatException('Unsupported gRPC frame');
      }
    }
    if (grpcStatus == '16') return PulseSessionState.expired;
    if (grpcStatus == '7') return PulseSessionState.forbidden;
    if (grpcStatus == null || int.tryParse(grpcStatus) == null) {
      return PulseSessionState.invalidResponse;
    }
    if (grpcStatus != '0') return PulseSessionState.unavailable;
    if (message == null) return PulseSessionState.invalidResponse;
    final fields = _fields(message);
    if (fields.containsKey(1) && fields.containsKey(2)) {
      return PulseSessionState.invalidResponse;
    }
    if (fields.containsKey(2)) {
      // A notAuthorized oneof is meaningful even with an empty login URL.
      _fields(fields[2]!);
      return PulseSessionState.expired;
    }
    final authorized = fields[1];
    if (authorized == null) return PulseSessionState.invalidResponse;
    final user = _fields(authorized)[1];
    if (user == null) return PulseSessionState.invalidResponse;
    final id = _fields(user)[1];
    if (id == null || utf8.decode(id).trim().isEmpty) {
      return PulseSessionState.invalidResponse;
    }
    return PulseSessionState.valid;
  } on FormatException {
    return PulseSessionState.invalidResponse;
  }
}

Map<int, Uint8List> _fields(Uint8List bytes) {
  var offset = 0;
  int varint() {
    var value = 0;
    for (var shift = 0; shift < 70; shift += 7) {
      if (offset >= bytes.length) {
        throw const FormatException('Truncated protobuf');
      }
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return value;
    }
    throw const FormatException('Invalid protobuf varint');
  }

  final result = <int, Uint8List>{};
  while (offset < bytes.length) {
    final tag = varint();
    if (tag >> 3 == 0) throw const FormatException('Invalid protobuf tag');
    final wire = tag & 7;
    if (wire == 0) {
      varint();
      continue;
    }
    final size = switch (wire) {
      1 => 8,
      2 => varint(),
      5 => 4,
      _ => throw const FormatException('Unsupported protobuf wire'),
    };
    if (size < 0 || size > bytes.length - offset) {
      throw const FormatException('Truncated protobuf field');
    }
    if (wire == 2) {
      result[tag >> 3] = Uint8List.sublistView(bytes, offset, offset + size);
    }
    offset += size;
  }
  return result;
}
