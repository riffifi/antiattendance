# Device delivery

After app changes, run the relevant checks, build a release APK with
`flutter build apk --release`, and install it on the connected Pixel.
Discover its current device ID with `adb devices -l`. Install with
`adb -s <device> install -r build/app/outputs/flutter-apk/app-release.apk`.
Preserve installed app data; do not uninstall or clear storage to resolve an
installation failure. Report the release build and installation result.
