import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'accounts.dart';

const _prefix = 'PULSE-SESSIONS:1';
const _chunkSize = 600;
const _maxFrames = 256;
const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

class SessionTransfer {
  const SessionTransfer(this.frames, this.code);
  final List<String> frames;
  final String code;
}

Future<SessionTransfer> createSessionTransfer(List<SavedAccount> accounts) async {
  if (accounts.isEmpty) {
    throw const FormatException('No accounts selected.');
  }
  final random = Random.secure();
  final code = List.generate(16, (_) => _alphabet[random.nextInt(32)]).join();
  final nonce = List.generate(12, (_) => random.nextInt(256));
  final id = base64Url.encode(List.generate(6, (_) => random.nextInt(256)));
  final json = jsonEncode({
    'created': DateTime.now().toUtc().millisecondsSinceEpoch,
    'accounts': accounts.map((a) => {'label': a.label, 'cookie': a.cookie}).toList(),
  });
  final plain = ZLibEncoder().convert(utf8.encode(json));
  if (plain.length > 120000) {
    throw const FormatException('Too many sessions for QR transfer.');
  }
  final key = await _key(code);
  final box = await AesGcm.with256bits().encrypt(
    plain,
    secretKey: key,
    nonce: nonce,
  );
  final encoded = base64Url.encode([...nonce, ...box.mac.bytes, ...box.cipherText]);
  final count = (encoded.length / _chunkSize).ceil();
  if (count > _maxFrames) {
    throw const FormatException('Too many sessions for QR transfer.');
  }
  return SessionTransfer([
    for (var i = 0; i < count; i++)
      '$_prefix:$id:${i + 1}:$count:${encoded.substring(i * _chunkSize, min((i + 1) * _chunkSize, encoded.length))}',
  ], code);
}

Future<SecretKey> _key(String code) async {
  final normalized = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (normalized.length != 16 ||
      normalized.split('').any((c) => !_alphabet.contains(c))) {
    throw const FormatException('Invalid transfer code.');
  }
  final digest = await Sha256().hash(utf8.encode(normalized));
  return SecretKey(digest.bytes);
}

class SessionTransferCollector {
  String? _id;
  int? _total;
  final _parts = <int, String>{};

  int get received => _parts.length;
  int get total => _total ?? 0;
  bool get complete => _total != null && _parts.length == _total;

  bool accept(String value) {
    final match = RegExp(
      r'^PULSE-SESSIONS:1:([A-Za-z0-9_-]{8}):([1-9][0-9]*):([1-9][0-9]*):([A-Za-z0-9_=-]+)$',
    ).firstMatch(value);
    if (match == null) return false;
    final id = match.group(1)!;
    final index = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    final part = match.group(4)!;
    if (index == null || total == null || total > _maxFrames ||
        index > total || part.length > _chunkSize) return false;
    if (_id != null && (_id != id || _total != total)) return false;
    _id = id;
    _total = total;
    final old = _parts[index];
    if (old != null) return old == part;
    _parts[index] = part;
    return true;
  }

  Future<List<SavedAccount>> decrypt(String code) async {
    if (!complete) throw const FormatException('Transfer is incomplete.');
    try {
      final encoded = [for (var i = 1; i <= _total!; i++) _parts[i]!].join();
      final bytes = base64Url.decode(encoded);
      if (bytes.length < 29) throw const FormatException('Invalid transfer.');
      final box = SecretBox(
        bytes.sublist(28),
        nonce: bytes.sublist(0, 12),
        mac: Mac(bytes.sublist(12, 28)),
      );
      final plain = await AesGcm.with256bits().decrypt(box, secretKey: await _key(code));
      final decoded = jsonDecode(utf8.decode(ZLibDecoder().convert(plain)));
      if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid transfer.');
      final created = decoded['created'];
      final entries = decoded['accounts'];
      if (created is! int || entries is! List || entries.isEmpty || entries.length > 200) {
        throw const FormatException('Invalid transfer.');
      }
      final age = DateTime.now().toUtc().difference(
        DateTime.fromMillisecondsSinceEpoch(created, isUtc: true),
      );
      if (age > const Duration(minutes: 30) || age < const Duration(minutes: -5)) {
        throw const FormatException('Transfer expired.');
      }
      final accounts = <SavedAccount>[];
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (entry is! Map<String, dynamic> ||
            entry['label'] is! String ||
            entry['cookie'] is! String) {
          throw const FormatException('Invalid transfer.');
        }
        final label = entry['label'] as String;
        final cookie = entry['cookie'] as String;
        if (label.trim().isEmpty || label.length > 60 ||
            cookie.length > 32000 ||
            !cookie.startsWith('.AspNetCore.Cookies=')) {
          throw const FormatException('Invalid transfer.');
        }
        accounts.add(SavedAccount(id: '$i', label: label, cookie: cookie));
      }
      return accounts;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Wrong code or damaged transfer.');
    }
  }
}
