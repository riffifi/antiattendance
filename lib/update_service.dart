import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const releasesPage = 'https://github.com/riffifi/antiattendance/releases';
const _latestApi =
    'https://api.github.com/repos/riffifi/antiattendance/releases/latest';

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.page,
    this.apk,
    this.apkSha256,
    this.apkSize,
  });
  final String tag;
  final Uri page;
  final Uri? apk;
  final String? apkSha256;
  final int? apkSize;
}

class GitHubUpdateService {
  GitHubUpdateService({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  Future<AppRelease?> latest() async {
    final response = await _client
        .get(
          Uri.parse(_latestApi),
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'AntiAttendance-update-check',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw FormatException('GitHub returned HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > 1024 * 1024) {
      throw const FormatException('Release response is too large.');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic> || data['tag_name'] is! String) {
      throw const FormatException('Invalid release response.');
    }
    final tag = data['tag_name'] as String;
    final page = _releaseUri(
      data['html_url'],
      '/riffifi/antiattendance/releases/tag/',
    );
    if (page == null) throw const FormatException('Invalid release URL.');
    final apks = <({Uri url, String? sha256, int? size})>[];
    final assets = data['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name'];
        if (name is! String || !name.toLowerCase().endsWith('.apk')) continue;
        final uri = _releaseUri(
          asset['browser_download_url'],
          '/riffifi/antiattendance/releases/download/',
        );
        if (uri != null) {
          final digest = asset['digest'];
          final size = asset['size'];
          apks.add((
            url: uri,
            sha256:
                digest is String &&
                    RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)
                ? digest.substring(7).toLowerCase()
                : null,
            size: size is int && size > 0 ? size : null,
          ));
        }
      }
    }
    ({Uri url, String? sha256, int? size})? apk;
    if (apks.length == 1) {
      apk = apks.single;
    } else if (apks.length > 1) {
      for (final item in apks) {
        final name = item.url.pathSegments.last.toLowerCase();
        if (name.contains('universal') || name == 'app-release.apk') {
          apk = item;
          break;
        }
      }
    }
    return AppRelease(
      tag: tag,
      page: page,
      apk: apk?.url,
      apkSha256: apk?.sha256,
      apkSize: apk?.size,
    );
  }

  void close() => _client.close();
}

Uri? _releaseUri(Object? value, String prefix) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      !uri.path.startsWith(prefix)) {
    return null;
  }
  return uri;
}

bool isNewerRelease(String tag, String installedVersion, String buildNumber) {
  final release = _versionParts(tag);
  final installed = _versionParts(installedVersion);
  if (release == null || installed == null) return false;
  for (var i = 0; i < 3; i++) {
    if (release[i] != installed[i]) return release[i]! > installed[i]!;
  }
  return release[3] != null && release[3]! > (int.tryParse(buildNumber) ?? 0);
}

List<int?>? _versionParts(String value) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$')
      .firstMatch(value);
  if (match == null) return null;
  return [
    for (var i = 1; i <= 4; i++)
      match.group(i) == null ? null : int.parse(match.group(i)!),
  ];
}

class UpdateController extends ChangeNotifier {
  UpdateController({
    GitHubUpdateService? service,
    Future<PackageInfo> Function()? packageInfo,
  }) : _service = service ?? GitHubUpdateService(),
       _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
       _ownsService = service == null;

  final GitHubUpdateService _service;
  final Future<PackageInfo> Function() _packageInfo;
  final bool _ownsService;
  bool checking = false;
  bool checked = false;
  bool _disposed = false;
  String? error;
  String? installedVersion;
  AppRelease? release;
  bool updateAvailable = false;

  Future<void> check() async {
    if (checking) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final info = await _packageInfo();
      final latest = await _service.latest();
      if (_disposed) return;
      installedVersion = info.version;
      release = latest;
      updateAvailable =
          latest != null &&
          isNewerRelease(latest.tag, info.version, info.buildNumber);
      checked = true;
    } catch (_) {
      if (!_disposed) error = 'Could not check for updates.';
    } finally {
      checking = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsService) _service.close();
    super.dispose();
  }
}
