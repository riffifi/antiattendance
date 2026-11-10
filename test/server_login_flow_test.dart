import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/server_login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'server_contract_test.dart' show response, tokenGrant;
import 'server_workspace_test.dart' show settleNetwork;

void main() {
  for (final linked in [true, false]) {
    testWidgets('QR claim closes on success and explains linked=$linked', (
      tester,
    ) async {
      AaId.reset();
      FlutterSecureStorage.setMockInitialValues({});
      var claims = 0;
      AaId.httpClient = () => MockClient((request) async {
        if (request.url.path.endsWith('/claim')) {
          claims++;
          return response(tokenGrant(linked: linked));
        }
        if (request.method == 'POST') {
          return response({'id': 'job', 'token': 'secret'});
        }
        expect(request.headers['x-login-token'], 'secret');
        return response({'status': 'complete'});
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      const ServerLoginPage(address: defaultAaIdUrl),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settleNetwork(tester);
      expect(claims, 1);
      expect(AaId.signedIn, isTrue);
      if (linked) {
        expect(find.byType(ServerLoginPage), findsNothing);
      } else {
        expect(find.textContaining('AA ID sign-in succeeded'), findsOneWidget);
        expect(find.text('New code'), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      AaId.reset();
    });
  }
}
