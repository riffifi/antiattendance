import 'dart:convert';

import 'package:antiattendance/update_service.dart';
import 'package:antiattendance/settings_page.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FakeReleases extends GitHubUpdateService {
  FakeReleases(this.release);
  final AppRelease? release;
  @override
  Future<AppRelease?> latest() async => release;
}

void main() {
  test('GitHub 404 means there is no published release yet', () async {
    final service = GitHubUpdateService(
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/riffifi/antiattendance/releases/latest',
        );
        return http.Response('{"message":"Not Found"}', 404);
      }),
    );
    expect(await service.latest(), isNull);
    service.close();
  });

  test('release details use only URLs from this GitHub repository', () async {
    final service = GitHubUpdateService(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'tag_name': 'v1.2.0',
            'html_url':
                'https://github.com/riffifi/antiattendance/releases/tag/v1.2.0',
            'assets': [
              {
                'name': 'app-release.apk',
                'browser_download_url': 'https://github.com/riffifi/antiattendance/releases/download/v1.2.0/app-release.apk',
              },
              {
                'name': 'other.apk',
                'browser_download_url': 'https://example.com/unsafe.apk',
              },
            ],
          }),
          200,
        ),
      ),
    );
    final release = (await service.latest())!;
    expect(release.tag, 'v1.2.0');
    expect(release.apk!.host, 'github.com');
    expect(release.apk!.pathSegments.last, 'app-release.apk');
    service.close();
  });

  test('version comparison checks release tag and installed build', () {
    expect(isNewerRelease('v1.2.0', '1.1.0', '2'), isTrue);
    expect(isNewerRelease('v1.1.0', '1.1.0', '2'), isFalse);
    expect(isNewerRelease('v1.1.0+3', '1.1.0', '2'), isTrue);
    expect(isNewerRelease('v1.0.9', '1.1.0', '2'), isFalse);
    expect(isNewerRelease('nightly', '1.1.0', '2'), isFalse);
  });

  test('controller reports a newer release after automatic check', () async {
    final release = AppRelease(
      tag: 'v1.2.0',
      page: Uri.parse(
        'https://github.com/riffifi/antiattendance/releases/tag/v1.2.0',
      ),
    );
    final service = FakeReleases(release);
    final controller = UpdateController(
      service: service,
      packageInfo: () async => PackageInfo(
        appName: 'AntiAttendance',
        packageName: 'antiattendance',
        version: '1.1.0',
        buildNumber: '2',
      ),
    );
    await controller.check();
    expect(controller.updateAvailable, isTrue);
    expect(controller.installedVersion, '1.1.0');
    controller.dispose();
    service.close();
  });

  testWidgets('Settings shows an available GitHub release', (tester) async {
    final service = FakeReleases(
      AppRelease(
        tag: 'v1.2.0',
        page: Uri.parse(
          'https://github.com/riffifi/antiattendance/releases/tag/v1.2.0',
        ),
      ),
    );
    final controller = UpdateController(
      service: service,
      packageInfo: () async => PackageInfo(
        appName: 'AntiAttendance',
        packageName: 'antiattendance',
        version: '1.1.0',
        buildNumber: '2',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          store: AppSettingsStore(),
          language: null,
          onLanguageChanged: (_) {},
          updates: controller,
        ),
      ),
    );
    await controller.check();
    await tester.pumpAndSettle();
    expect(find.text('Version v1.2.0 is available'), findsOneWidget);
    expect(find.text('Open release'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    service.close();
  });
}
