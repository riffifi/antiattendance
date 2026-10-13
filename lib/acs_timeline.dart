import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nfc_pass_client/src/grpc_web_response.dart';
import 'package:nfc_pass_client/src/nfc_session_cookie.dart';

const _acsTimelinePath =
    '/rtu_tc.rtu_attend.humanpass.HumanPassService/GetHumanAcsTimeline';

class AcsEvent {
  const AcsEvent({
    required this.id,
    required this.at,
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.toName,
  });

  final String id;
  final DateTime at;
  final String fromId;
  final String fromName;
  final String toId;
  final String toName;
}

class AcsTimelineClient {
  AcsTimelineClient({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<AcsEvent>> timeline({
    required String cookie,
    required String humanId,
    required DateTime from,
    required DateTime to,
  }) async {
    final request = _message([
      _field(1, utf8.encode(humanId)),
      _field(2, _message([
        _timestamp(1, from),
        _timestamp(2, to),
      ])),
      _varintField(3, 1),
      _varintField(4, 2),
    ]);
    final response = await _client
        .post(
          Uri.https('pulse.mirea.ru', _acsTimelinePath),
          headers: {
            'content-type': 'application/grpc-web+proto',
            'accept': 'application/grpc-web+proto',
            'x-grpc-web': '1',
            'cookie': nfcSessionCookieHeader(cookie),
          },
          body: _frame(request),
        )
        .timeout(const Duration(seconds: 15));
    final payload = parseGrpcWebResponse(
      Uint8List.fromList(response.bodyBytes),
      headers: response.headers,
    );
    return _parseEvents(payload);
  }

  void close() => _client.close();
}

List<AcsEvent> _parseEvents(Uint8List bytes) {
  final events = <AcsEvent>[];
  for (final field in _fields(bytes)) {
    if (field.number != 1 || field.wire != 2) continue;
    final event = _lastFields(field.bytes!);
    final id = _string(event, 1);
    final time = _timestamp(event[2]?.bytes);
    final transition = _lastFields(event[3]?.bytes ?? Uint8List(0));
    final from = _location(transition[1]?.bytes);
    final to = _location(transition[2]?.bytes);
    if (id != null && time != null && from != null && to != null) {
      events.add(
        AcsEvent(
          id: id,
          at: time,
          fromId: from.$1,
          fromName: from.$2,
          toId: to.$1,
          toName: to.$2,
        ),
      );
    }
  }
  return events;
}

(String, String)? _location(Uint8List? bytes) {
  if (bytes == null) return null;
  final fields = _lastFields(bytes);
  final id = _string(fields, 1);
  final name = _string(fields, 2);
  return id == null || name == null ? null : (id, name);
}

DateTime? _timestamp(Uint8List? bytes) {
  if (bytes == null) return null;
  final fields = _lastFields(bytes);
  final seconds = fields[1]?.varint;
  if (seconds == null) return null;
  final nanos = fields[2]?.varint ?? 0;
  return DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000 + nanos ~/ 1000000,
    isUtc: true,
  );
}

String? _string(Map<int, _Field> fields, int number) {
  final bytes = fields[number]?.bytes;
  return bytes == null ? null : utf8.decode(bytes);
}

class _Field {
  const _Field(this.number, this.wire, {this.bytes, this.varint});
  final int number;
  final int wire;
  final Uint8List? bytes;
  final int? varint;
}

List<_Field> _fields(Uint8List bytes) {
  final result = <_Field>[];
  var offset = 0;
  while (offset < bytes.length) {
    final tag = _readVarint(bytes, offset);
    offset = tag.$2;
    final number = tag.$1 >> 3;
    final wire = tag.$1 & 7;
    if (wire == 0) {
      final value = _readVarint(bytes, offset);
      offset = value.$2;
      result.add(_Field(number, wire, varint: value.$1));
    } else if (wire == 2) {
      final length = _readVarint(bytes, offset);
      offset = length.$2;
      if (length.$1 > bytes.length - offset) {
        throw const FormatException('Invalid ACS timeline response.');
      }
      result.add(_Field(
        number,
        wire,
        bytes: Uint8List.sublistView(bytes, offset, offset + length.$1),
      ));
      offset += length.$1;
    } else {
      throw const FormatException('Unsupported ACS timeline field.');
    }
  }
  return result;
}

Map<int, _Field> _lastFields(Uint8List bytes) {
  final result = <int, _Field>{};
  for (final field in _fields(bytes)) {
    result[field.number] = field;
  }
  return result;
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
  throw const FormatException('Invalid ACS timeline protobuf.');
}

Uint8List _frame(Uint8List payload) => Uint8List.fromList([
  0,
  (payload.length >> 24) & 0xff,
  (payload.length >> 16) & 0xff,
  (payload.length >> 8) & 0xff,
  payload.length & 0xff,
  ...payload,
]);

Uint8List _message(List<List<int>> fields) =>
    Uint8List.fromList(fields.expand((field) => field).toList());

List<int> _field(int number, List<int> value) => [
  ..._varint(number << 3 | 2),
  ..._varint(value.length),
  ...value,
];

List<int> _varintField(int number, int value) => [
  ..._varint(number << 3),
  ..._varint(value),
];

List<int> _timestamp(int number, DateTime value) => _field(
  number,
  _message([
    _varintField(1, value.toUtc().millisecondsSinceEpoch ~/ 1000),
    _varintField(
      2,
      (value.toUtc().millisecond * 1000000) +
          (value.toUtc().microsecond * 1000),
    ),
  ]),
);

List<int> _varint(int value) {
  final result = <int>[];
  while (value >= 128) {
    result.add((value & 0x7f) | 0x80);
    value >>= 7;
  }
  return [...result, value];
}
