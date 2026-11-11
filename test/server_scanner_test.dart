import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_login_page.dart';
import 'package:antiattendance/server_scan_queue.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'server_contract_test.dart' show response;
import 'server_workspace_test.dart' show settleNetwork;

String qr(String token) => 'https://pulse.mirea.ru/lesson?token=$token';
const people = [
  {'id': 'a', 'label': 'Alex'},
  {'id': 'b', 'label': 'Sam'},
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AaId.reset();
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(AaId.reset);

  test(
    'server queue deduplicates frames and excludes confirmed people',
    () async {
      final sent = <Map<String, dynamic>>[];
      final client = SessionServerClient(
        'https://aa.example',
        client: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          sent.add(body);
          expect(r.url.path, '/site/mark');
          return response({
            'results': [
              for (final id in body['account_ids'])
                {
                  'id': id,
                  'state': id == 'a' || sent.length == 2
                      ? 'approved'
                      : 'waiting',
                  'message': 'Result',
                },
            ],
          });
        }),
      );
      addTearDown(client.close);
      final queue = ServerScanQueue(
        api: AaServerApi(client),
        people: people,
        lessonStart: 123,
      );
      addTearDown(queue.dispose);
      await queue.accept(qr('one'));
      await queue.accept(qr('one'));
      expect(queue.remaining, 1);
      expect(sent, hasLength(1));
      await queue.accept(qr('two'));
      expect(sent.last['account_ids'], ['b']);
      expect(sent.last['lesson_start'], 123);
      expect(queue.remaining, 0);
      await queue.accept(qr('three'));
      expect(sent, hasLength(2));
    },
  );

  test(
    'uncertain mutation blocks later frames until an explicit retry',
    () async {
      var calls = 0;
      final client = SessionServerClient(
        'https://aa.example',
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return response({
              'selected_lesson': {'lesson_start': 123},
              'people': people,
            });
          }
          calls++;
          return response({'detail': 'Lost response'}, 503);
        }),
      );
      addTearDown(client.close);
      final queue = ServerScanQueue(
        api: AaServerApi(client),
        people: people,
        lessonStart: 123,
      );
      addTearDown(queue.dispose);
      await queue.accept(qr('one'));
      await queue.accept(qr('two'));
      expect(calls, 1);
      expect(queue.blocked, isTrue);
      await queue.retry();
      await queue.accept(qr('one'));
      expect(calls, 2);
    },
  );

  test(
    'a class conflict cannot be retried in the old camera context',
    () async {
      var calls = 0;
      final client = SessionServerClient(
        'https://aa.example',
        client: MockClient((_) async {
          calls++;
          return response({}, 409);
        }),
      );
      addTearDown(client.close);
      final queue = ServerScanQueue(
        api: AaServerApi(client),
        people: people,
        lessonStart: 123,
      );
      addTearDown(queue.dispose);
      await queue.accept(qr('one'));
      expect(queue.canRetry, isFalse);
      await queue.retry();
      await queue.accept(qr('two'));
      expect(calls, 1);
    },
  );

  test('an in-flight batch cannot overlap another detection', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final client = SessionServerClient(
      'https://aa.example',
      client: MockClient((_) async {
        calls++;
        return pending.future;
      }),
    );
    addTearDown(client.close);
    final queue = ServerScanQueue(
      api: AaServerApi(client),
      people: people,
      lessonStart: 123,
    );
    addTearDown(queue.dispose);
    final first = queue.accept(qr('one'));
    await Future<void>.delayed(Duration.zero);
    await queue.accept(qr('two'));
    expect(calls, 1);
    pending.complete(
      response({
        'results': [
          {'id': 'a', 'state': 'approved'},
          {'id': 'b', 'state': 'approved'},
        ],
      }),
    );
    await first;
    expect(queue.confirmed, 2);
  });

  test(
    'queue starts with existing confirmations and sends only remaining people',
    () async {
      final sent = <String>[];
      final client = SessionServerClient(
        'https://aa.example',
        client: MockClient((r) async {
          sent.addAll(
            (jsonDecode(r.body)['account_ids'] as List).cast<String>(),
          );
          return response({
            'results': [
              {'id': 'b', 'state': 'approved'},
            ],
          });
        }),
      );
      addTearDown(client.close);
      final queue = ServerScanQueue(
        api: AaServerApi(client),
        lessonStart: 123,
        people: [
          {
            ...people.first,
            'mark': {
              'state': 'approved',
              'message': 'Присутствие подтверждено',
            },
          },
          people.last,
        ],
      );
      addTearDown(queue.dispose);
      expect(queue.confirmed, 1);
      await queue.accept(qr('one'));
      expect(sent, ['b']);
      expect(queue.confirmed, 2);
    },
  );

  for (final allConfirmed in [false, true]) {
    test(
      'retry reconciles lost results before resuming; all confirmed: $allConfirmed',
      () async {
        final pending = Completer<http.Response>();
        var reads = 0;
        final sent = <List<dynamic>>[];
        final client = SessionServerClient(
          'https://aa.example',
          client: MockClient((r) async {
            if (r.method == 'GET') {
              reads++;
              expect(r.url.queryParameters['lesson_start'], '123');
              return pending.future;
            }
            sent.add(jsonDecode(r.body)['account_ids'] as List);
            if (sent.length == 1) {
              return response({'detail': 'Lost response'}, 503);
            }
            return response({
              'results': [
                {'id': 'b', 'state': 'approved'},
              ],
            });
          }),
        );
        addTearDown(client.close);
        final queue = ServerScanQueue(
          api: AaServerApi(client),
          people: people,
          lessonStart: 123,
        );
        addTearDown(queue.dispose);
        await queue.accept(qr('one'));
        final retry = queue.retry();
        await Future<void>.delayed(Duration.zero);
        expect(queue.checkingResults, isTrue);
        await queue.retry();
        await queue.accept(qr('two'));
        expect(sent, hasLength(1));
        pending.complete(
          response({
            'selected_lesson': {'lesson_start': 123},
            'people': [
              {
                'id': 'a',
                'mark': {'state': 'approved'},
              },
              {
                'id': 'b',
                'mark': {'state': allConfirmed ? 'approved' : 'waiting'},
              },
              {
                'id': 'not-selected',
                'mark': {'state': 'approved'},
              },
            ],
          }),
        );
        await retry;
        expect(reads, 1);
        expect(queue.blocked, isFalse);
        expect(queue.results.containsKey('not-selected'), isFalse);
        expect(sent, hasLength(1));
        await queue.accept(qr('two'));
        if (allConfirmed) {
          expect(sent, hasLength(1));
        } else {
          expect(sent.last, ['b']);
        }
        expect(queue.remaining, 0);
      },
    );
  }

  for (final classChanged in [false, true]) {
    test(
      'failed retry keeps scanning blocked; class changed: $classChanged',
      () async {
        var posts = 0, reads = 0;
        final client = SessionServerClient(
          'https://aa.example',
          client: MockClient((r) async {
            if (r.method == 'POST') {
              posts++;
              return response({}, 503);
            }
            reads++;
            return classChanged
                ? response({
                    'selected_lesson': {'lesson_start': 456},
                    'people': [],
                  })
                : response({}, 503);
          }),
        );
        addTearDown(client.close);
        final queue = ServerScanQueue(
          api: AaServerApi(client),
          people: people,
          lessonStart: 123,
        );
        addTearDown(queue.dispose);
        await queue.accept(qr('one'));
        await queue.retry();
        expect(queue.blocked, isTrue);
        expect(queue.canRetry, !classChanged);
        await queue.accept(qr('two'));
        expect(posts, 1);
        expect(reads, 1);
      },
    );
  }

  for (final trusted in [true, false]) {
    testWidgets(
      'browser sign-in link is offered only for a MIREA challenge ($trusted)',
      (tester) async {
        final png = base64Encode(File('icon/app_icon.png').readAsBytesSync());
        const url =
            'https://sso.mirea.ru/realms/mirea/qr-code-auth/scan?qrToken=example';
        Uri? opened;
        AaId.httpClient = () => MockClient(
          (r) async => r.method == 'POST'
              ? response({'id': 'job', 'token': 'secret'})
              : response({
                  'status': 'login',
                  'qr': trusted ? url : 'https://example.com/steal',
                  'qr_png': 'data:image/png;base64,$png',
                }),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ServerLoginPage(
              address: defaultAaIdUrl,
              browserOpener: (uri, _) async {
                opened = uri;
                return true;
              },
            ),
          ),
        );
        await settleNetwork(tester);
        if (trusted) {
          expect(find.text('Open in browser'), findsOneWidget);
          await tester.tap(find.text('Open in browser'));
          await settleNetwork(tester);
          expect(opened.toString(), url);
        } else {
          expect(find.text('Open in browser'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
