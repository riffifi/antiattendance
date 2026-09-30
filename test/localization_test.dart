import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/l10n.dart';
import 'package:antiattendance/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptyAccounts extends AccountStore {
  @override
  Future<List<SavedAccount>> load() async => [];
}

void main() {
  const supported = [
    Locale('en'),
    Locale('ru'),
    Locale('fr'),
    Locale('pt'),
    Locale('zh'),
  ];
  const delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  for (final (language, attendance, confirmed, count) in [
    ('fr', 'Présences', 'Présence confirmée', '2 cours'),
    ('pt', 'Presenças', 'Presença confirmada', '2 aulas'),
    ('zh', '考勤', '考勤已确认', '2 节课'),
    ('ru', 'Посещаемость', 'Отметка подтверждена', '2 занятия'),
  ]) {
    testWidgets('$language uses its interface and status text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: supported,
          localizationsDelegates: delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  Text(tr(context, 'Посещаемость', 'Attendance')),
                  Text(trMessage(context, 'Присутствие подтверждено')),
                  Text(classCountLabel(context, 2)),
                  Text(
                    trf(context, 'Удалить {name}?', 'Delete {name}?', {
                      'name': 'Anya',
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text(attendance), findsOneWidget);
      expect(find.text(confirmed), findsOneWidget);
      expect(find.text(count), findsOneWidget);
      expect(find.textContaining('Anya'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in const ['fr', 'pt', 'zh']) {
    testWidgets('$language home fits a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: supported,
          localizationsDelegates: delegates,
          home: HomePage(store: EmptyAccounts()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final (phoneLocale, expected) in [
    (const Locale('fr', 'CD'), 'Présences'),
    (const Locale('pt', 'AO'), 'Presenças'),
    (const Locale('zh', 'CN'), '考勤'),
  ]) {
    testWidgets('$phoneLocale matches the supported language', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: phoneLocale,
          supportedLocales: supported,
          localizationsDelegates: delegates,
          home: Builder(
            builder: (context) =>
                Scaffold(body: Text(tr(context, 'Посещаемость', 'Attendance'))),
          ),
        ),
      );
      expect(find.text(expected), findsOneWidget);
    });
  }

  testWidgets('Russian class count uses natural endings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: supported,
        localizationsDelegates: delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                for (final count in [1, 2, 5, 11, 21])
                  Text(classCountLabel(context, count)),
              ],
            ),
          ),
        ),
      ),
    );
    for (final label in [
      '1 занятие',
      '2 занятия',
      '5 занятий',
      '11 занятий',
      '21 занятие',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
