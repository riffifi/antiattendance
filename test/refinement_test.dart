import 'dart:async';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_passes_page.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'server_contract_test.dart' show response, tokenGrant;
import 'server_workspace_test.dart' show settleNetwork;

void main() {
  setUp(() async {
    AaId.reset();
    FlutterSecureStorage.setMockInitialValues({});
    await AaId.acceptLogin(
      defaultAaIdUrl,
      AaIdSession.fromServer(tokenGrant()),
    );
  });
  tearDown(AaId.reset);

  for (final mode in AppThemeMode.values) {
    testWidgets('${mode.name} inputs use matching surfaces, ink and focus', (
      tester,
    ) async {
      for (final enabled in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(mode),
            home: Scaffold(
              body: CampusTextField(
                label: 'Name',
                placeholder: 'Your name',
                enabled: enabled,
                leading: const Icon(Icons.person),
                trailing: const Icon(Icons.clear),
              ),
            ),
          ),
        );
        final decoration = tester
            .widget<InputDecorator>(find.byType(InputDecorator))
            .decoration;
        final ink = tester
            .widget<EditableText>(find.byType(EditableText))
            .style
            .color!;
        final theme = tester.element(find.byType(CampusTextField)).brockmann;
        expect(
          decoration.fillColor,
          mode == AppThemeMode.light
              ? (enabled ? const Color(0xffe4e4e4) : const Color(0xffd0d0d0))
              : enabled
              ? theme.surface
              : theme.background,
        );
        if (enabled) {
          expect(
            BrockmannThemeData.contrast(ink, decoration.fillColor!),
            greaterThan(7),
          );
          expect(decoration.prefixIconColor, theme.foreground);
          expect(
            (decoration.focusedBorder! as OutlineInputBorder).borderSide.color,
            theme.accent,
          );
        }
        if (mode != AppThemeMode.light) {
          expect(decoration.fillColor, isNot(Colors.white));
          expect(
            BrockmannThemeData.contrast(
              decoration.hintStyle!.color!,
              decoration.fillColor!,
            ),
            greaterThan(3),
          );
        }
      }
    });
  }

  testWidgets('inline errors stay readable in dark and AMOLED fields', (
    tester,
  ) async {
    for (final mode in [AppThemeMode.dark, AppThemeMode.amoled]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(mode),
          home: const Scaffold(
            body: CampusTextField(label: 'Name', error: 'Check this value'),
          ),
        ),
      );
      final decoration = tester
          .widget<InputDecorator>(find.byType(InputDecorator))
          .decoration;
      expect(
        BrockmannThemeData.contrast(
          decoration.errorStyle!.color!,
          decoration.fillColor!,
        ),
        greaterThan(4.5),
      );
    }
  });

  testWidgets(
    'person search accepts @username and keyboard submit; editing clears errors',
    (tester) async {
      final queries = <String>[];
      final client = SessionServerClient(
        defaultSessionServerUrl,
        client: MockClient((r) async {
          queries.add(r.url.queryParameters['q']!);
          return response({'detail': 'Temporary failure'}, 503);
        }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ServerPersonSearchPage(api: AaServerApi(client)),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(CampusTextField);
      await tester.enterText(field, ' @Alex ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleNetwork(tester);
      expect(queries, ['alex']);
      expect(
        find.text('Could not get a response. Check your connection.'),
        findsOneWidget,
      );
      await tester.enterText(field, 'sam');
      await tester.pump();
      expect(
        find.text('Could not get a response. Check your connection.'),
        findsNothing,
      );
      expect(queries, hasLength(1));
    },
  );
  testWidgets(
    'technical input flags reach the editor without changing normal name entry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Column(
              children: [
                CampusTextField(label: 'Name'),
                CampusTextField(
                  label: 'Username',
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ],
            ),
          ),
        ),
      );
      final fields = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .toList();
      expect(fields.first.autocorrect, isTrue);
      expect(fields.first.enableSuggestions, isTrue);
      expect(fields.last.autocorrect, isFalse);
      expect(fields.last.enableSuggestions, isFalse);
    },
  );

  testWidgets(
    'clearing a pending person search keeps focus and rejects its late result',
    (tester) async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final client = SessionServerClient(
        defaultSessionServerUrl,
        client: MockClient((r) async {
          calls++;
          return pending.future;
        }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ServerPersonSearchPage(api: AaServerApi(client)),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(CampusTextField);
      final originalWidth = tester.getSize(find.byType(EditableText)).width;
      await tester.enterText(field, 'alex');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(calls, 1);
      await tester.tap(find.byKey(const ValueKey('clear-person-search')));
      await tester.pumpAndSettle();
      expect(tester.widget<CampusTextField>(field).controller!.text, isEmpty);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(tester.getSize(find.byType(EditableText)).width, originalWidth);
      pending.complete(
        response({
          'people': [
            {
              'account_id': 'person',
              'label': 'Late result',
              'username': 'alex',
            },
          ],
        }),
      );
      await settleNetwork(tester);
      expect(find.text('Late result'), findsNothing);
      expect(calls, 1);
      expect(find.byKey(const ValueKey('clear-person-search')), findsNothing);
    },
  );
}
