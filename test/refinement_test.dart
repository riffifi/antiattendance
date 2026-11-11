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
}
