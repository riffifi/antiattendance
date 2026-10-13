import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:antiattendance/pulse_user.dart';

void main() {
  test('decodes the authorized user ID from GetMeInfo', () {
    const humanId = '11111111-1111-4111-8111-111111111111';
    final user = _message([
      _field(1, utf8.encode(humanId)),
    ]);
    final authorized = _message([_field(1, user)]);
    final response = _message([_field(1, authorized)]);

    expect(
      decodeHumanId(response),
      humanId,
    );
  });
}

Uint8List _message(List<List<int>> fields) =>
    Uint8List.fromList(fields.expand((field) => field).toList());

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
