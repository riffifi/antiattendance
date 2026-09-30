import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:cryptography/cryptography.dart';

import 'accounts.dart';

const nearbyServiceType = '_pulse-sessions._tcp';
const _maxBody = 200000;

Future<String> receiverCode(List<int> publicKey) async {
  final hash = await Sha256().hash(publicKey);
  return hash.bytes
      .take(6)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

Future<Map<String, String>> encryptNearby(
  List<SavedAccount> accounts,
  List<int> receiverPublicKey,
) async {
  if (accounts.isEmpty ||
      accounts.length > 200 ||
      receiverPublicKey.length != 32) {
    throw const FormatException('Invalid receiver or empty transfer.');
  }
  final exchange = X25519();
  final sender = await exchange.newKeyPair();
  final senderPublic = await sender.extractPublicKey();
  final secret = await exchange.sharedSecretKey(
    keyPair: sender,
    remotePublicKey: SimplePublicKey(
      receiverPublicKey,
      type: KeyPairType.x25519,
    ),
  );
  final nonce = List.generate(12, (_) => Random.secure().nextInt(256));
  final plain = utf8.encode(
    jsonEncode({
      'created': DateTime.now().toUtc().millisecondsSinceEpoch,
      'accounts': accounts
          .map(
            (a) => {
              'label': a.label,
              'cookie': a.cookie,
              'groupId': a.groupId,
              'groupName': a.groupName,
            },
          )
          .toList(),
    }),
  );
  if (plain.length > 120000) throw const FormatException('Transfer too large.');
  final box = await AesGcm.with256bits().encrypt(
    plain,
    secretKey: secret,
    nonce: nonce,
  );
  return {
    'sender': base64Url.encode(senderPublic.bytes),
    'nonce': base64Url.encode(nonce),
    'mac': base64Url.encode(box.mac.bytes),
    'data': base64Url.encode(box.cipherText),
  };
}

Future<List<SavedAccount>> decryptNearby(
  Map<String, dynamic> packet,
  KeyPair receiver,
) async {
  try {
    final sender = base64Url.decode(packet['sender'] as String);
    final nonce = base64Url.decode(packet['nonce'] as String);
    final mac = base64Url.decode(packet['mac'] as String);
    final data = base64Url.decode(packet['data'] as String);
    if (sender.length != 32 ||
        nonce.length != 12 ||
        mac.length != 16 ||
        data.length > 120000) {
      throw const FormatException('Invalid transfer.');
    }
    final secret = await X25519().sharedSecretKey(
      keyPair: receiver,
      remotePublicKey: SimplePublicKey(sender, type: KeyPairType.x25519),
    );
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(data, nonce: nonce, mac: Mac(mac)),
      secretKey: secret,
    );
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid transfer.');
    }
    final created = decoded['created'];
    final entries = decoded['accounts'];
    if (created is! int ||
        entries is! List ||
        entries.isEmpty ||
        entries.length > 200) {
      throw const FormatException('Invalid transfer.');
    }
    final age = DateTime.now().toUtc().difference(
      DateTime.fromMillisecondsSinceEpoch(created, isUtc: true),
    );
    if (age > const Duration(minutes: 30) ||
        age < const Duration(minutes: -5)) {
      throw const FormatException('Transfer expired.');
    }
    final result = <SavedAccount>[];
    for (var i = 0; i < entries.length; i++) {
      final item = entries[i];
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid transfer.');
      }
      final label = item['label'];
      final cookie = item['cookie'];
      if (label is! String ||
          cookie is! String ||
          label.trim().isEmpty ||
          label.length > 60 ||
          cookie.length > 120000 ||
          !cookie.startsWith('.AspNetCore.Cookies=')) {
        throw const FormatException('Invalid transfer.');
      }
      result.add(
        SavedAccount(
          id: '$i',
          label: label,
          cookie: cookie,
          groupId: item['groupId'] is int ? item['groupId'] as int : null,
          groupName: item['groupName'] is String
              ? item['groupName'] as String
              : null,
        ),
      );
    }
    return result;
  } catch (_) {
    throw const FormatException('Invalid or damaged transfer.');
  }
}

class NearbyReceiver {
  NearbyReceiver();

  KeyPair? _keyPair;
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  final _incoming = StreamController<List<SavedAccount>>.broadcast();
  bool _pending = false;
  bool _stopped = false;
  String? code;
  Stream<List<SavedAccount>> get incoming => _incoming.stream;

  void clearPending() => _pending = false;

  Future<void> start() async {
    try {
      _keyPair = await X25519().newKeyPair();
      if (_stopped) return;
      final publicKey =
          (await _keyPair!.extractPublicKey() as SimplePublicKey).bytes;
      code = await receiverCode(publicKey);
      if (_stopped) return;
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv6,
          0,
          v6Only: false,
        );
      } on SocketException {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      if (_stopped) {
        await _server!.close(force: true);
        return;
      }
      _server!.listen(_handle);
      _broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: 'Pulse $code',
          type: nearbyServiceType,
          port: _server!.port,
          attributes: {'pk': base64Url.encode(publicKey)},
        ),
        printLogs: false,
      );
      await _broadcast!.initialize();
      if (_stopped) return;
      await _broadcast!.start();
      if (_stopped) await _broadcast!.stop();
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method != 'POST' ||
        request.uri.path != '/v1/transfer' ||
        _pending) {
      request.response.statusCode = HttpStatus.conflict;
      await request.response.close();
      return;
    }
    try {
      final body = BytesBuilder(copy: false);
      await for (final chunk in request.timeout(const Duration(seconds: 10))) {
        if (body.length + chunk.length > _maxBody) {
          throw const FormatException('Too large.');
        }
        body.add(chunk);
      }
      final packet = jsonDecode(utf8.decode(body.takeBytes()));
      if (packet is! Map<String, dynamic>) {
        throw const FormatException('Invalid packet.');
      }
      final accounts = await decryptNearby(packet, _keyPair!);
      _pending = true;
      _incoming.add(accounts);
      request.response.statusCode = HttpStatus.accepted;
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
    }
    await request.response.close();
  }

  Future<void> stop() async {
    _stopped = true;
    try {
      if (_broadcast?.isReady == true && _broadcast?.isStopped == false) {
        await _broadcast!.stop();
      }
    } catch (_) {
      // Discovery can already be stopping during page disposal.
    }
    final server = _server;
    _server = null;
    await server?.close(force: true);
    if (!_incoming.isClosed) await _incoming.close();
  }
}

Future<void> sendNearby(
  BonsoirService service,
  List<SavedAccount> accounts,
) async {
  final encodedKey = service.attributes['pk'];
  final addresses = <String>{
    ...service.hostAddresses.where(
      (a) => InternetAddress.tryParse(a)?.type == InternetAddressType.IPv4,
    ),
    ...service.hostAddresses.where(
      (a) => InternetAddress.tryParse(a)?.type != InternetAddressType.IPv4,
    ),
    if (service.hostname != null) service.hostname!,
  };
  if (addresses.isEmpty || encodedKey == null || service.port <= 0) {
    throw const FormatException('Receiver not reachable.');
  }
  final packet = await encryptNearby(accounts, base64Url.decode(encodedKey));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    for (final host in addresses) {
      try {
        final url = Uri(
          scheme: 'http',
          host: host,
          port: service.port,
          path: '/v1/transfer',
        );
        final request = await client
            .postUrl(url)
            .timeout(const Duration(seconds: 8));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(packet));
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        await response.drain<void>();
        if (response.statusCode == HttpStatus.accepted) return;
        if (response.statusCode == HttpStatus.conflict) break;
      } catch (_) {
        // Try another advertised address, such as IPv4 after IPv6.
      }
    }
    throw const FormatException('Receiver did not accept the transfer.');
  } finally {
    client.close(force: true);
  }
}
