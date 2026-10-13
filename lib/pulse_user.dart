import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nfc_pass_client/src/grpc_web_response.dart';

const _getMeInfoPath = '/rtu_tc.rtu_attend.app.UserService/GetMeInfo';

class PulseUserClient {
  PulseUserClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String?> getHumanId(String cookie) async {
    final request = _field(1, utf8.encode('https://pulse.mirea.ru/services'));
    final frame = Uint8List(5 + request.length)
      ..[0] = 0
      ..buffer.asByteData().setUint32(1, request.length)
      ..setRange(5, 5 + request.length, request);
    final response = await _client
        .post(
          Uri.https('pulse.mirea.ru', _getMeInfoPath),
          headers: {
            'content-type': 'application/grpc-web+proto',
            'accept': 'application/grpc-web+proto',
            'x-grpc-web': '1',
            'cookie': cookie,
          },
          body: frame,
        )
        .timeout(const Duration(seconds: 15));
    final payload = parseGrpcWebResponse(
      Uint8List.fromList(response.bodyBytes),
      headers: response.headers,
    );
    return decodeHumanId(payload);
  }

  void close() => _client.close();
}

String? decodeHumanId(Uint8List bytes) {
  final response = _lastFields(bytes);
  final authorized = response[1]?.bytes;
  if (authorized == null) return null;
  final user = _lastFields(_lastFields(authorized)[1]?.bytes ?? Uint8List(0));
  final userId = user[1]?.bytes;
  if (userId == null) return null;
  final value = utf8.decode(userId);
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)
      ? value
      : null;
}

class _Field {
  const _Field({this.bytes});
  final Uint8List? bytes;
}

Map<int, _Field> _lastFields(Uint8List bytes) {
  final fields = <int, _Field>{};
  var offset = 0;
  while (offset < bytes.length) {
    final tag = _readVarint(bytes, offset);
    offset = tag.$2;
    final number = tag.$1 >> 3;
    final wire = tag.$1 & 7;
    if (wire != 2) {
      throw const FormatException('Unsupported GetMeInfo protobuf field.');
    }
    final length = _readVarint(bytes, offset);
    offset = length.$2;
    if (length.$1 > bytes.length - offset) {
      throw const FormatException('Invalid GetMeInfo protobuf response.');
    }
    fields[number] = _Field(
      bytes: Uint8List.sublistView(bytes, offset, offset + length.$1),
    );
    offset += length.$1;
  }
  return fields;
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
  throw const FormatException('Invalid GetMeInfo protobuf response.');
}

List<int> _field(int number, List<int> value) => [
  ..._varint(number << 3 | 2),
  ..._varint(value.length),
  ...value,
];

List<int> _varint(int value) {
  final result = <int>[];
  while (value >= 128) {
    result.add((value & 0x7f) | 0x80);
    value >>= 7;
  }
  return [...result, value];
}
