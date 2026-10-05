import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const pulseHost = 'pulse.mirea.ru';
const pulseLoginUrl =
    'https://pulse.mirea.ru/api/auth/login?redirectUri=https%3A%2F%2Fpulse.mirea.ru%2Fservices&rememberMe=True';

String attendanceTokenFromQr(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      !{'pulse.mirea.ru', 'attendance-app.mirea.ru'}.contains(uri.host) ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Это не ссылка на посещаемость Пульса.');
  }
  final tokens = uri.queryParametersAll['token'];
  if (tokens == null ||
      tokens.length != 1 ||
      tokens.single.isEmpty ||
      tokens.single.length > 4096) {
    throw const FormatException('В QR-коде нет корректного токена занятия.');
  }
  return tokens.single;
}

String pulseSessionCookie(Map<String, String> cookies) {
  final base = cookies['.AspNetCore.Cookies'];
  if (base == null || base.isEmpty) {
    throw const FormatException('Сессия Пульса не найдена.');
  }
  final chunkMatch = RegExp(r'^chunks-([1-9][0-9]*)$').firstMatch(base);
  final count = chunkMatch == null ? 0 : int.parse(chunkMatch.group(1)!);
  if (base.startsWith('chunks-') && chunkMatch == null || count > 64) {
    throw const FormatException('Некорректная сессия Пульса.');
  }
  final result = <String>[];
  for (var i = 0; i <= count; i++) {
    final name = i == 0 ? '.AspNetCore.Cookies' : '.AspNetCore.CookiesC$i';
    final value = cookies[name];
    if (value == null ||
        value.isEmpty ||
        !RegExp(r'^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]+$')
            .hasMatch(value)) {
      throw const FormatException('Сессия Пульса неполная.');
    }
    result.add('$name=$value');
  }
  return result.join('; ');
}

enum ApprovalState { approved, waiting, rejected }

class ApprovalResult {
  const ApprovalResult(this.state, this.message, {this.lessonId});
  final ApprovalState state;
  final String message;
  final String? lessonId;
}

class PulseApi {
  PulseApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<ApprovalResult> approve(String token, String cookie) async {
    final request = _field(1, utf8.encode(token));
    final frame = Uint8List(5 + request.length)
      ..[0] = 0
      ..buffer.asByteData().setUint32(1, request.length)
      ..setRange(5, 5 + request.length, request);
    final httpRequest =
        http.Request(
            'POST',
            Uri.https(
              pulseHost,
              '/rtu_tc.attendance.api.AttendanceService/SelfApproveAttendanceThroughQRCode',
            ),
          )
          ..followRedirects = false
          ..headers.addAll({
            'content-type': 'application/grpc-web+proto',
            'accept': 'application/grpc-web+proto',
            'x-grpc-web': '1',
            'cookie': cookie,
          })
          ..bodyBytes = frame;
    final response = await _client
        .send(httpRequest)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 302 ||
        response.statusCode == 303) {
      throw const PulseApiException(
        'Сессия истекла. Войдите в аккаунт снова.',
        sessionExpired: true,
      );
    }
    if (response.statusCode != 200) {
      throw PulseApiException('Пульс вернул HTTP ${response.statusCode}.');
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (chunk.length > 1024 * 1024 - body.length) {
        throw const PulseApiException('Ответ Пульса слишком большой.');
      }
      body.add(chunk);
    }
    Uint8List? message;
    var grpcStatus = response.headers['grpc-status'];
    final bytes = body.takeBytes();
    var offset = 0;
    while (offset + 5 <= bytes.length) {
      final flag = bytes[offset];
      final size = ByteData.sublistView(
        bytes,
        offset + 1,
        offset + 5,
      ).getUint32(0);
      offset += 5;
      if (size > bytes.length - offset) {
        throw const PulseApiException('Некорректный ответ Пульса.');
      }
      final content = Uint8List.sublistView(bytes, offset, offset + size);
      offset += size;
      if (flag == 0) {
        message = content;
      } else if (flag == 0x80) {
        final trailers = ascii.decode(content, allowInvalid: true);
        grpcStatus =
            RegExp(
              r'grpc-status:\s*(\d+)',
              caseSensitive: false,
            ).firstMatch(trailers)?.group(1) ??
            grpcStatus;
      } else {
        throw const PulseApiException('Неподдерживаемый ответ Пульса.');
      }
    }
    if (offset != bytes.length || grpcStatus != null && grpcStatus != '0') {
      throw PulseApiException(
        grpcStatus == '16'
            ? 'Сессия истекла. Войдите в аккаунт снова.'
            : 'Пульс отклонил запрос (gRPC ${grpcStatus ?? 'формат'}).',
        sessionExpired: grpcStatus == '16',
      );
    }
    if (message == null) {
      throw const PulseApiException('Пульс не вернул результат.');
    }
    return decodeApproval(message);
  }

  void close() => _client.close();
}

class PulseApiException implements Exception {
  const PulseApiException(this.message, {this.sessionExpired = false});
  final bool sessionExpired;
  final String message;
  @override
  String toString() => message;
}

ApprovalResult decodeApproval(Uint8List bytes) {
  final outer = _fields(bytes);
  if (outer.containsKey(2)) {
    final approved = _fields(outer[2]!);
    final id = approved[1] == null ? null : utf8.decode(approved[1]!);
    return ApprovalResult(
      ApprovalState.approved,
      'Присутствие подтверждено',
      lessonId: id,
    );
  }
  if (outer.containsKey(1)) {
    final reasonBytes = _fields(outer[1]!)[1];
    final reason = reasonBytes == null ? 0 : _readVarint(reasonBytes, 0).$1;
    return switch (reason) {
      1 => const ApprovalResult(
        ApprovalState.rejected,
        'Неверный или просроченный QR-код',
      ),
      2 => const ApprovalResult(
        ApprovalState.waiting,
        'Ожидается подтверждение',
      ),
      3 => const ApprovalResult(
        ApprovalState.rejected,
        'Аккаунт не записан на занятие',
      ),
      4 => const ApprovalResult(
        ApprovalState.rejected,
        'Журнал занятия в архиве',
      ),
      5 => const ApprovalResult(
        ApprovalState.rejected,
        'Присутствие в кампусе не подтверждено',
      ),
      6 => const ApprovalResult(
        ApprovalState.rejected,
        'Указано уважительное отсутствие',
      ),
      7 => const ApprovalResult(
        ApprovalState.rejected,
        'Указано нарушение распорядка',
      ),
      _ => const ApprovalResult(
        ApprovalState.rejected,
        'Пульс не подтвердил присутствие',
      ),
    };
  }
  throw const PulseApiException('Неизвестный результат Пульса.');
}

Uint8List _field(int number, List<int> value) => Uint8List.fromList([
  ..._varint(number << 3 | 2),
  ..._varint(value.length),
  ...value,
]);

List<int> _varint(int value) {
  final result = <int>[];
  while (value >= 128) {
    result.add(value & 0x7f | 0x80);
    value >>= 7;
  }
  return [...result, value];
}

(int, int) _readVarint(Uint8List bytes, int offset) {
  var value = 0;
  var shift = 0;
  while (offset < bytes.length && shift < 64) {
    final byte = bytes[offset++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) return (value, offset);
    shift += 7;
  }
  throw const PulseApiException('Некорректный protobuf-ответ.');
}

Map<int, Uint8List> _fields(Uint8List bytes) {
  final fields = <int, Uint8List>{};
  var offset = 0;
  while (offset < bytes.length) {
    final (tag, afterTag) = _readVarint(bytes, offset);
    offset = afterTag;
    final wire = tag & 7;
    if (wire == 2) {
      final (length, afterLength) = _readVarint(bytes, offset);
      offset = afterLength;
      if (length > bytes.length - offset) {
        throw const PulseApiException('Некорректный protobuf-ответ.');
      }
      fields[tag >> 3] = Uint8List.sublistView(bytes, offset, offset + length);
      offset += length;
    } else if (wire == 0) {
      final start = offset;
      offset = _readVarint(bytes, offset).$2;
      fields[tag >> 3] = Uint8List.sublistView(bytes, start, offset);
    } else {
      throw const PulseApiException('Неподдерживаемый protobuf-ответ.');
    }
  }
  return fields;
}
