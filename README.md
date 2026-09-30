# AntiAttendance

Flutter app for Android and iOS. It stores several independently signed-in Пульс sessions on one device and submits one lecture QR code for the selected accounts. Each account owner signs in interactively through МИРЭА or imports a saved session from another phone. Passwords are never saved by this app; session cookies are saved with `flutter_secure_storage`. The interface follows the phone language: Russian, English, French, Portuguese, or Simplified Chinese (English is the fallback), with an optional override in **Settings**.

## Use

1. Tap **Добавить** and finish **Войти через МИРЭА** for each account. Give each session a local label.
2. Select accounts and tap **Сканировать QR** for one immediate submission, or paste the Пульс URL and tap **Отправить**.
3. Tap **Режим очереди** to keep the camera on a rotating lecture QR. The app immediately submits each new QR for accounts still waiting or rejected, and removes an account from the queue only when Пульс confirms attendance. A stationary QR may be retried after a short pause. Close the camera when finished.
4. Use **Войти снова** if a session expires, or **Удалить** to remove it from the device.

The sign-in screen has **− / +** controls below the WebView to shrink or enlarge the MIREA page when a form is cut off on a phone. Open the gear icon for language settings and the About screen.

## Updates

The app checks the [latest GitHub release](https://github.com/riffifi/antiattendance/releases) when it starts. A dot on Settings means a newer version is available. Settings can check again manually. On Android, **Install update** downloads the release APK into the app cache, verifies its size and GitHub SHA-256 digest when supplied, and opens the Android installer. The user must confirm installation and may need to allow installs from this app in Android settings. The release page remains available as a fallback. On iOS, **Open release** opens the release page. Until the first release is published, Settings shows **No releases yet**.

To publish an Android update, increase `version:` in `pubspec.yaml`, set the GitHub Actions secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`, then push a tag matching the version, such as `v1.2.1` for `version: 1.2.1+5`. The [release workflow](.github/workflows/release-android.yml) runs analysis and tests, builds one signed APK, and attaches it to a GitHub release. Keep the same keystore for every release; Android requires the same signing key to upgrade an installed release. A locally installed debug build has a different signing key and must be removed before installing a signed release.

## Groups and schedule

Open an account's **⋮ → Выбрать группу** menu, search for its МИРЭА group, and choose it. The **Расписание** tab opens on today's classes from the university schedule service. Tap a day in the week strip, use the arrows for other weeks, or tap **Today** to return. Pull down to refresh.

Tap a scheduled class to scan its QR in queue mode or paste a QR link (useful for the Linux UI preview). All saved accounts assigned to that group are submitted. Only Пульс responses that confirm attendance appear under that class. These are local confirmation records on this device, linked to the class you opened; the schedule service does not provide an authoritative attendance roster or a mapping from its calendar event IDs to Пульс lesson IDs. Scans started on the attendance tab appear as other confirmations for that day, without being attributed to a particular class. Group assignments transfer with sessions; attendance history stays on the device.

## Transfer sessions

**Nearby:** On each receiving phone, tap **Получить → Получить рядом**. On the sending phone, select the accounts and tap **Передать → Передать рядом**. Keep the phones on the same Wi-Fi network. The sender sees a list of receivers and can select several. Compare each receiver's displayed code with the code in the sender's list before sending. Each receiver reviews the account names and confirms the import. The payload is encrypted for each receiver with an ephemeral X25519 key exchange and AES-GCM; no cloud service is used. A receiver must keep the app open while receiving. Local network discovery can be blocked by guest Wi-Fi isolation or denied local network permission.

**QR fallback:** Tap **Передать → Передать через QR** on the sender and **Получить → Сканировать QR передачи** on the receiver. Keep the receiver's camera pointed at the sender until every QR frame is collected. The sender then taps **Показать код** and gives the code to the receiver. The QR frames are encrypted; the code is separate from the QR display. The receiver reviews the account names before import. The transfer expires after 30 minutes.

Session transfer grants another device access to the saved accounts until their Пульс sessions expire or are revoked. Transfer only to trusted devices and people. Existing identical sessions on the receiver are skipped. Group assignments are included in both transfer methods.

The app sends the QR token to Пульс's `SelfApproveAttendanceThroughQRCode` gRPC-Web method. Пульс may reject an account that is not enrolled in the lecture or whose presence in the campus access system is not recorded. The API is inferred from the Пульс web client as of September 2026; it is not a documented public integration and may change.

## Development

```sh
/home/leo/flutter/bin/flutter pub get
/home/leo/flutter/bin/flutter analyze
/home/leo/flutter/bin/flutter test
/home/leo/flutter/bin/flutter run -d linux
/home/leo/flutter/bin/dart run flutter_launcher_icons
```

Linux is for previewing the UI, testing a pasted QR link, and testing nearby transfer. Browser login and camera scanning are available on Android and iOS. The Linux build requires `libsecret-1-dev` (on Ubuntu: `sudo apt install libsecret-1-dev`) for the secure-storage plugin. An Android SDK and accepted licenses are needed for APK builds. iOS builds require macOS and Xcode. iOS needs local network permission for nearby transfer; the app declares its Bonjour service in `Info.plist`.

`third_party/flutter_inappwebview_android` is the upstream 1.1.3 Android implementation with its two ProGuard defaults changed to `proguard-android-optimize.txt` for Android Gradle Plugin 9.1. Its upstream license is included in that directory.

Launcher icons are generated from `icon/app_icon.png`. The top bar uses `icon/brand.svg`, a copy of the supplied SVG with only unsupported metadata removed.

The reference repository contains NFC pass enrollment API code and UI, but it explicitly excludes the private native Android HCE/APDU implementation (`tool/verify_private_native_boundary.dart`). This app does not present campus NFC passes.
