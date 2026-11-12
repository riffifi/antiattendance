import 'dart:convert';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_schedule_cache.dart';
import 'package:antiattendance/server_schedule_page.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'server_contract_test.dart' show response, tokenGrant;
import 'server_workspace_test.dart' show settleNetwork;

Map<String, dynamic> timetable() => {
  'group_name': 'Group A',
  'days': [
    {
      'date': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 3))
          .toIso8601String()
          .substring(0, 10),
      'today': true,
      'lessons': [
        {
          'start': '09:00',
          'end': '10:00',
          'subject': 'Cached class',
          'state': 'now',
          'cookie': 'SECRET',
        },
      ],
    },
  ],
  'people': ['PRIVATE'],
  'token': 'SECRET',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AaId.reset();
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(AaId.reset);

  test(
    'cache isolates scopes and whitelists only timetable metadata',
    () async {
      final cache = ServerScheduleCache();
      await cache.save('server|alice|group-a', 0, timetable());
      expect(await cache.load('server|bob|group-a', 0), isNull);
      expect(await cache.load('server|alice|group-b', 0), isNull);
      expect(await cache.load('other-server|alice|group-a', 0), isNull);
      final saved = (await cache.load('server|alice|group-a', 0))!;
      expect(saved.data['group_name'], 'Group A');
      final raw = jsonEncode(await const FlutterSecureStorage().readAll());
      for (final value in [
        'SECRET',
        'PRIVATE',
        'cookie',
        'token',
        'today',
        '"now"',
      ]) {
        expect(raw, isNot(contains(value)));
      }
    },
  );

  test(
    'cache retains five weeks per scope and eight contexts overall',
    () async {
      var now = DateTime.utc(2026, 11, 12);
      final cache = ServerScheduleCache(now: () => now);
      for (var week = 0; week < 7; week++) {
        await cache.save('scope', week, timetable());
        now = now.add(const Duration(microseconds: 1));
      }
      expect(await cache.load('scope', 0), isNull);
      expect(await cache.load('scope', 2), isNotNull);
      for (var scope = 0; scope < 9; scope++) {
        await cache.save('scope-$scope', 0, timetable());
      }
      expect(await cache.load('scope', 2), isNull);
      expect(await cache.load('scope-0', 0), isNull);
      expect(await cache.load('scope-8', 0), isNotNull);
    },
  );

  test(
    'old data expires and cache index cannot delete unrelated credentials',
    () async {
      var now = DateTime.utc(2026, 11, 12);
      final cache = ServerScheduleCache(now: () => now);
      await const FlutterSecureStorage().write(
        key: 'credential',
        value: 'protected',
      );
      await const FlutterSecureStorage().write(
        key: 'schedule_cache_scopes_v1',
        value: '["credential"]',
      );
      await cache.save('scope', 0, timetable());
      now = now.add(const Duration(days: 15));
      expect(await cache.load('scope', -2), isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'credential'),
        'protected',
      );
    },
  );

  test('Moscow week keys remain stable across UTC midnight', () async {
    var now = DateTime.utc(2026, 11, 15, 22);
    final cache = ServerScheduleCache(now: () => now);
    await cache.save('scope', 0, timetable());
    now = DateTime.utc(2026, 11, 16, 1);
    expect(await cache.load('scope', 0), isNotNull);
  });

  test('an in-flight week remains keyed to its requested Monday', () async {
    var now = DateTime.utc(2026, 11, 15, 20);
    final cache = ServerScheduleCache(now: () => now);
    now = DateTime.utc(2026, 11, 15, 22);
    await cache.save('scope', 0, timetable(), monday: '2026-11-09');
    expect(await cache.load('scope', -1), isNotNull);
    expect(await cache.load('scope', 0), isNull);
  });

  testWidgets('an open timetable keeps its week across Moscow Monday', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 15, 20);
    final weeks = <String?>[];
    final client = SessionServerClient(
      'https://aa.example',
      client: MockClient((r) async {
        weeks.add(r.url.queryParameters['week']);
        return response(timetable());
      }),
    );
    addTearDown(client.close);
    final key = GlobalKey<ServerSchedulePageState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ServerSchedulePage(
            key: key,
            api: AaServerApi(client),
            active: true,
            now: () => now,
          ),
        ),
      ),
    );
    await settleNetwork(tester);
    now = DateTime.utc(2026, 11, 15, 22);
    await tester.runAsync(() => key.currentState!.refresh());
    await settleNetwork(tester);
    expect(weeks, ['0', '-1']);
  });

  for (final forbidden in [false, true]) {
    testWidgets(
      'schedule uses a saved week offline, but drops denied data: $forbidden',
      (tester) async {
        await AaId.acceptLogin(
          defaultAaIdUrl,
          AaIdSession.fromServer(tokenGrant()),
        );
        final cache = ServerScheduleCache();
        final scope =
            'https://aa.example|${AaId.session!.userId}|${AaId.session!.groupId}|null';
        await tester.runAsync(() => cache.save(scope, 0, timetable()));
        final client = SessionServerClient(
          'https://aa.example',
          client: MockClient((r) async => response({}, forbidden ? 403 : 503)),
        );
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ServerSchedulePage(
                api: AaServerApi(client),
                active: true,
                cache: cache,
              ),
            ),
          ),
        );
        await settleNetwork(tester);
        expect(
          find.text('Cached class'),
          forbidden ? findsNothing : findsOneWidget,
        );
        expect(
          find.textContaining('Saved schedule'),
          forbidden ? findsNothing : findsOneWidget,
        );
        if (forbidden) expect(await cache.load(scope, 0), isNull);
      },
    );
  }
}
