# Пульс · посещаемость

Flutter app for Android and iOS. It stores several independently signed-in Пульс sessions on one device and submits one lecture QR code for the selected accounts. Each account owner signs in interactively through МИРЭА on the device. Passwords are never saved by this app; session cookies are saved with `flutter_secure_storage`.

## Use

1. Tap **Добавить** and finish **Войти через МИРЭА** for each account. Give each session a local label.
2. Select accounts and tap **Сканировать QR** for one immediate submission, or paste the Пульс URL and tap **Отправить**.
3. Tap **Режим очереди** to keep the camera on a rotating lecture QR. The app immediately submits each new QR for accounts still waiting or rejected, and removes an account from the queue only when Пульс confirms attendance. A stationary QR may be retried after a short pause. Close the camera when finished.
4. Use **Войти снова** if a session expires, or **Удалить** to remove it from the device.

The app sends the QR token to Пульс's `SelfApproveAttendanceThroughQRCode` gRPC-Web method. Пульс may reject an account that is not enrolled in the lecture or whose presence in the campus access system is not recorded. The API is inferred from the Пульс web client as of September 2026; it is not a documented public integration and may change.

## Development

```sh
/home/leo/flutter/bin/flutter pub get
/home/leo/flutter/bin/flutter analyze
/home/leo/flutter/bin/flutter test
/home/leo/flutter/bin/flutter run -d linux
```

Linux is for previewing the UI and testing a pasted QR link. Browser login and camera scanning are available on Android and iOS. The Linux build requires `libsecret-1-dev` (on Ubuntu: `sudo apt install libsecret-1-dev`) for the secure-storage plugin. An Android SDK and accepted licenses are needed for APK builds. iOS builds require macOS and Xcode.

`third_party/flutter_inappwebview_android` is the upstream 1.1.3 Android implementation with its two ProGuard defaults changed to `proguard-android-optimize.txt` for Android Gradle Plugin 9.1. Its upstream license is included in that directory.

The reference repository contains NFC pass enrollment API code, but its native Android HCE/APDU implementation is absent. This app does not present campus NFC passes.
