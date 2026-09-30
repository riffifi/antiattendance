import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/nearby_transfer.dart';
import 'package:antiattendance/session_transfer.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final random = Random(42);
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final accounts = [
    for (var i = 0; i < 12; i++)
      SavedAccount(
        id: '$i',
        label: 'Friend $i',
        groupId: 769,
        groupName: 'ИНБО-10-23',
        cookie:
            '.AspNetCore.Cookies=${List.generate(800, (_) => alphabet[random.nextInt(alphabet.length)]).join()}',
      ),
  ];

  test(
    'QR frames reassemble out of order and need the transfer code',
    () async {
      final transfer = await createSessionTransfer(accounts);
      expect(transfer.frames.length, greaterThan(1));
      final collector = SessionTransferCollector();
      for (final frame in transfer.frames.reversed) {
        expect(collector.accept(frame), isTrue);
      }
      expect(collector.complete, isTrue);
      expect(collector.accept(transfer.frames.first), isTrue);
      await expectLater(
        collector.decrypt('AAAAAAAAAAAAAAAA'),
        throwsFormatException,
      );
      final imported = await collector.decrypt(transfer.code);
      expect(imported.map((a) => a.label), accounts.map((a) => a.label));
      expect(imported.map((a) => a.cookie), accounts.map((a) => a.cookie));
      expect(imported.map((a) => a.groupId), everyElement(769));
    },
  );

  test('nearby payload decrypts only for selected receiver', () async {
    final receiver = await X25519().newKeyPair();
    final other = await X25519().newKeyPair();
    final publicKey = await receiver.extractPublicKey();
    final packet = await encryptNearby(accounts, publicKey.bytes);
    final imported = await decryptNearby(packet, receiver);
    expect(imported.map((a) => a.cookie), accounts.map((a) => a.cookie));
    expect(imported.map((a) => a.groupName), everyElement('ИНБО-10-23'));
    await expectLater(decryptNearby(packet, other), throwsFormatException);
  });

  test(
    'nearby sender delivers encrypted sessions over a local socket',
    () async {
      final receiver = await X25519().newKeyPair();
      final publicKey = await receiver.extractPublicKey();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final delivered = Completer<List<SavedAccount>>();
      server.listen((request) async {
        try {
          final packet = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          delivered.complete(await decryptNearby(packet, receiver));
          request.response.statusCode = HttpStatus.accepted;
        } catch (error) {
          delivered.completeError(error);
          request.response.statusCode = HttpStatus.badRequest;
        }
        await request.response.close();
      });
      final service = BonsoirService(
        name: 'Test receiver',
        type: nearbyServiceType,
        hostAddresses: ['127.0.0.1'],
        port: server.port,
        attributes: {'pk': base64Url.encode(publicKey.bytes)},
      );
      await sendNearby(service, accounts);
      final imported = await delivered.future;
      expect(imported.map((a) => a.cookie), accounts.map((a) => a.cookie));
    },
  );
}
