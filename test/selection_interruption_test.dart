import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/expressive.dart';
import 'package:antiattendance/group_picker_page.dart';
import 'package:antiattendance/schedule_api.dart';
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

class _Groups extends ScheduleApi {
  @override
  Future<List<ScheduleGroup>> searchGroups(String query) async => [
    const ScheduleGroup(id: 42, name: 'Group A'),
  ];
}

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

  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext) choose,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    body: Column(
                      children: [
                        const Text('Picker host'),
                        TextButton(
                          onPressed: () => choose(context),
                          child: const Text('Choose'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text('Open host'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a repeated choice callback cannot pop the page behind the picker',
    (tester) async {
      String? selected;
      await host(tester, (context) async {
        selected = await showChoicePage<String>(
          context,
          title: 'Pick',
          options: const [ChoiceOption(value: 'a', label: 'Option A')],
        );
      });
      final row = tester.widget<CampusListItem>(find.byType(CampusListItem));
      row.onTap!();
      row.onTap!();
      await tester.pumpAndSettle();
      expect(selected, 'a');
      expect(find.text('Picker host'), findsOneWidget);
    },
  );

  testWidgets('group result selection completes once during route dismissal', (
    tester,
  ) async {
    final api = _Groups();
    addTearDown(api.close);
    ScheduleGroup? selected;
    await host(tester, (context) async {
      selected = await Navigator.of(context).push<ScheduleGroup>(
        MaterialPageRoute(builder: (_) => GroupPickerPage(api: api)),
      );
    });
    await tester.enterText(find.byType(CampusTextField), 'group');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final row = tester.widget<CampusListItem>(find.byType(CampusListItem));
    row.onTap!();
    row.onTap!();
    await tester.pumpAndSettle();
    expect(selected?.id, 42);
    expect(find.text('Picker host'), findsOneWidget);
  });

  testWidgets('person result selection completes once during route dismissal', (
    tester,
  ) async {
    final client = SessionServerClient(
      defaultSessionServerUrl,
      client: MockClient(
        (r) async => response({
          'people': [
            {'account_id': 'person-a', 'label': 'Alex', 'username': 'alex'},
          ],
        }),
      ),
    );
    addTearDown(client.close);
    String? selected;
    await host(tester, (context) async {
      selected = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => ServerPersonSearchPage(api: AaServerApi(client)),
        ),
      );
    });
    await tester.enterText(find.byType(CampusTextField), 'alex');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settleNetwork(tester);
    final row = tester.widget<CampusListItem>(find.byType(CampusListItem));
    row.onTap!();
    row.onTap!();
    await tester.pumpAndSettle();
    expect(selected, 'person-a');
    expect(find.text('Picker host'), findsOneWidget);
  });

  testWidgets(
    'touching the selected tab acknowledges the press without selecting twice',
    (tester) async {
      var selected = 0, changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => BrockmannSegmentedControl<int>(
                options: const [0, 1],
                value: selected,
                labelFor: (value) => value == 0 ? 'One' : 'Two',
                onChanged: (value) => update(() {
                  selected = value;
                  changes++;
                }),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      expect(changes, 0);
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(changes, 1);
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(changes, 1);
    },
  );
}
