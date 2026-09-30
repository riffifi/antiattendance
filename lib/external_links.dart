import 'package:url_launcher/url_launcher.dart';

typedef UrlOpener = Future<bool> Function(Uri url, LaunchMode mode);

Future<bool> openWebPage(Uri url, {UrlOpener? opener}) async {
  final launch =
      opener ?? (Uri value, LaunchMode mode) => launchUrl(value, mode: mode);
  for (final mode in [
    LaunchMode.externalApplication,
    LaunchMode.inAppBrowserView,
    LaunchMode.platformDefault,
  ]) {
    try {
      if (await launch(url, mode)) return true;
    } catch (_) {
      // Another launch mode may work on this device.
    }
  }
  return false;
}
