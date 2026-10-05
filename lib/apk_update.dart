import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

const _maxApkBytes = 250 * 1024 * 1024;
const _installer = MethodChannel('antiattendance/installer');

class ApkUpdateDownloader {
  ApkUpdateDownloader({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  static bool _downloadActive = false;

  Future<File> download(
    AppRelease release, {
    Directory? cacheDirectory,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (_downloadActive)
      throw StateError('An update download is already running.');
    _downloadActive = true;
    try {
      return await _download(
        release,
        cacheDirectory: cacheDirectory,
        onProgress: onProgress,
      );
    } finally {
      _downloadActive = false;
    }
  }

  Future<File> _download(
    AppRelease release, {
    Directory? cacheDirectory,
    void Function(int received, int? total)? onProgress,
  }) async {
    final url = release.apk;
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith('/riffifi/antiattendance/releases/download/') ||
        !url.path.toLowerCase().endsWith('.apk')) {
      throw const FormatException('Invalid release APK URL.');
    }
    final response = await _client
        .send(http.Request('GET', url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw HttpException('APK download returned HTTP ${response.statusCode}');
    }
    final expectedSize = release.apkSize ?? response.contentLength;
    if (expectedSize != null && expectedSize > _maxApkBytes) {
      await response.stream.listen(null).cancel();
      throw const FormatException('Release APK is too large.');
    }

    final cache = cacheDirectory ?? await getTemporaryDirectory();
    final folder = Directory('${cache.path}/updates');
    await folder.create(recursive: true);
    final partial = File('${folder.path}/antiattendance-update.apk.part');
    final finished = File('${folder.path}/antiattendance-update.apk');
    final digestSink = _DigestSink();
    final hash = sha256.startChunkedConversion(digestSink);
    IOSink? sink;
    var received = 0;
    try {
      sink = partial.openWrite();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > _maxApkBytes) {
          throw const FormatException('Release APK is too large.');
        }
        hash.add(chunk);
        sink.add(chunk);
        onProgress?.call(received, expectedSize);
      }
      hash.close();
      await sink.flush();
      await sink.close();
      sink = null;
      if (received < 4 ||
          expectedSize != null && received != expectedSize ||
          release.apkSha256 != null &&
              digestSink.value.toString().toLowerCase() !=
                  release.apkSha256!.toLowerCase()) {
        throw const FormatException('Release APK failed verification.');
      }
      final header = await partial.openRead(0, 4).first;
      if (header.length != 4 ||
          header[0] != 0x50 ||
          header[1] != 0x4b ||
          header[2] != 0x03 ||
          header[3] != 0x04) {
        throw const FormatException('Downloaded file is not an APK.');
      }
      if (await finished.exists()) await finished.delete();
      return await partial.rename(finished.path);
    } finally {
      if (sink != null) await sink.close();
      if (await partial.exists()) await partial.delete();
    }
  }

  void close() => _client.close();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Future<void> openAndroidInstaller(File apk) =>
    _installer.invokeMethod<void>('installApk', {'path': apk.path});
