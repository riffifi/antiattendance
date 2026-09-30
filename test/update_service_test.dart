import 'dart:convert';
import 'dart:io';

import 'package:antiattendance/apk_update.dart';
import 'package:antiattendance/about_page.dart';
import 'package:antiattendance/external_links.dart';
import 'package:antiattendance/update_service.dart';
import 'package:antiattendance/settings_page.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final digest = List.filled(64, 'a').join();
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
                'size': 1234,
                'digest': 'sha256:$digest',
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
    expect(release.apkSize, 1234);
    expect(release.apkSha256, digest);
    service.close();
  });

  test('APK is downloaded and verified before installation', () async {
    final bytes = [0x50, 0x4b, 0x03, 0x04, ...utf8.encode('test apk')];
    final temp = await Directory.systemTemp.createTemp('antiattendance-test-');
    addTearDown(() => temp.delete(recursive: true));
    final downloader = ApkUpdateDownloader(
      client: MockClient((request) async {
        expect(request.url.host, 'github.com');
        return http.Response.bytes(bytes, 200);
      }),
    );
    final progress = <int>[];
    final apk = await downloader.download(
      AppRelease(
        tag: 'v1.2.0',
        page: Uri.parse(
          'https://github.com/riffifi/antiattendance/releases/tag/v1.2.0',
        ),
        apk: Uri.parse(
          'https://github.com/riffifi/antiattendance/releases/download/v1.2.0/app-release.apk',
        ),
        apkSize: bytes.length,
        apkSha256: sha256.convert(bytes).toString(),
      ),
      cacheDirectory: temp,
      onProgress: (received, _) => progress.add(received),
    );
    expect(await apk.readAsBytes(), bytes);
    expect(progress.last, bytes.length);
    downloader.close();
  });

  test(
    'APK download rejects a bad digest and removes the partial file',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'antiattendance-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final downloader = ApkUpdateDownloader(
        client: MockClient(
          (_) async => http.Response.bytes([0x50, 0x4b, 0x03, 0x04], 200),
        ),
      );
      await expectLater(
        downloader.download(
          AppRelease(
            tag: 'v1.2.0',
            page: Uri.parse(
              'https://github.com/riffifi/antiattendance/releases/tag/v1.2.0',
            ),
            apk: Uri.parse(
              'https://github.com/riffifi/antiattendance/releases/download/v1.2.0/app-release.apk',
            ),
            apkSha256: List.filled(64, '0').join(),
          ),
          cacheDirectory: temp,
        ),
        throwsFormatException,
      );
      expect(
        await File('${temp.path}/updates/antiattendance-update.apk.part')
            .exists(),
        isFalse,
      );
      downloader.close();
    },
  );

  test('web links fall back to another launch mode', () async {
    final modes = <LaunchMode>[];
    expect(
      await openWebPage(
        Uri.parse('https://github.com/riffifi/antiattendance'),
        opener: (_, mode) async {
          modes.add(mode);
          return mode == LaunchMode.inAppBrowserView;
        },
      ),
      isTrue,
    );
    expect(modes, [
      LaunchMode.externalApplication,
      LaunchMode.inAppBrowserView,
    ]);
  });

  testWidgets('About link reports a failure and copies the URL', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AboutPage(
          openGitHub: (_) async {
            calls++;
            return false;
          },
        ),
      ),
    );
    await tester.tap(find.text('GitHub'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    expect(find.text('Could not open GitHub. Link copied.'), findsOneWidget);
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
    await tester.scrollUntilVisible(
      find.text('Version v1.2.0 is available'),
      200,
    );
    expect(find.text('Version v1.2.0 is available'), findsOneWidget);
    expect(find.text('Open release'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    service.close();
  });
}
