# AntiAttendance

Flutter app for Android and iOS. It stores several independently signed-in Пульс sessions on one device and submits one lecture QR code for the selected accounts. Each account owner signs in interactively through МИРЭА or imports a saved session from another phone. Passwords are never saved by this app; session cookies are saved with `flutter_secure_storage`. The interface follows the phone language: Russian, English, French, Portuguese, or Simplified Chinese (English is the fallback), with an optional override in **Settings**.

## Use

1. Tap **Добавить** and finish **Войти через МИРЭА** for each account. Give each session a local label.
2. Select accounts and tap **Сканировать QR**. The scanner submits the first valid lecture QR immediately and keeps trying new QR tokens for accounts still waiting or rejected. It closes once all selected accounts are confirmed; you can close it sooner. Alternatively, paste the Пульс URL and tap **Отправить**.
3. Use **Войти снова** if a session expires, or **Удалить** to remove it from the device.

On Android, add either the 1×1 icon widget or the 2×1 labeled widget to the home screen for a one-tap shortcut to scanning with every saved account. The widget opens the scanner; attendance is sent only after it sees a lecture QR code. Launcher widgets are not available in the iOS build.

Use an account’s **⋮ → Rename** menu to change its local label without signing in again. With several accounts, the account list offers search by name or assigned group; search does not change the selected accounts.

The sign-in screen has **− / +** controls below the WebView to shrink or enlarge the MIREA page when a form is cut off on a phone. Settings offers Light, Dark, and Black (AMOLED) appearance. On Android 12+, **Phone colors (Monet)** applies the wallpaper accent to any of the three themes. Open the gear icon for appearance, language, and the About screen. Saved appearance and language load before the first Flutter frame, avoiding a flash of the default theme. All app screens use `material_3_expressive` 1.1.5 for navigation, app bars, buttons, fields, lists, selections, menus, dialogs, sheets, snackbars, and progress. Expressive tokens share the saved color scheme and Geist font. The pass picker integrates with Navigator back handling, sheet accessibility labels follow the app language, and the app respects reduced-motion settings. Material widgets use `material_ui`, as required by that package.

## Updates

The app checks the [latest GitHub release](https://github.com/riffifi/antiattendance/releases) when it starts. A dot on Settings means a newer version is available. Settings can check again manually. On Android, **Install update** downloads the release APK into the app cache, verifies its size and GitHub SHA-256 digest when supplied, and opens the Android installer. The user must confirm installation and may need to allow installs from this app in Android settings. The release page remains available as a fallback. On iOS, **Open release** opens the release page. Until the first release is published, Settings shows **No releases yet**.

To publish an Android update, increase `version:` in `pubspec.yaml`, set the GitHub Actions secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`, then push a tag matching the version, such as `v1.2.6` for `version: 1.2.6+4`. The [release workflow](.github/workflows/release-android.yml) runs analysis and tests, builds one signed APK, and attaches it to a GitHub release. Keep the same keystore for every release; Android requires the same signing key to upgrade an installed release. A locally installed debug build has a different signing key and must be removed before installing a signed release.

## Groups and schedule

Open an account's **⋮ → Выбрать группу** menu, search for its МИРЭА group, and choose it. The **Расписание** tab opens on today's classes from the university schedule service. Tap a day in the week strip, use the arrows for other weeks, or tap **Today** to return. Pull down to refresh.

Tap a scheduled class to scan its QR in queue mode or paste a QR link (useful for the Linux UI preview). All saved accounts assigned to that group are submitted. Only Пульс responses that confirm attendance appear under that class. These are local confirmation records on this device, linked to the class you opened; the schedule service does not provide an authoritative attendance roster or a mapping from its calendar event IDs to Пульс lesson IDs. Scans started on the attendance tab appear as other confirmations for that day, without being attributed to a particular class. Group assignments transfer with sessions; attendance history stays on the device.

## Transfer sessions

**Nearby:** On each receiving phone, tap **Получить → Получить рядом**. On the sending phone, select the accounts and tap **Передать → Передать рядом**. Keep the phones on the same Wi-Fi network. The sender sees a list of receivers and can select several. Compare each receiver's displayed code with the code in the sender's list before sending. Each receiver reviews the account names and confirms the import. The payload is encrypted for each receiver with an ephemeral X25519 key exchange and AES-GCM; no cloud service is used. A receiver must keep the app open while receiving. Local network discovery can be blocked by guest Wi-Fi isolation or denied local network permission.

**QR fallback:** Tap **Передать → Передать через QR** on the sender and **Получить → Сканировать QR передачи** on the receiver. Keep the receiver's camera pointed at the sender until every QR frame is collected. The sender then taps **Показать код** and gives the code to the receiver. The QR frames are encrypted; the code is separate from the QR display. The receiver reviews the account names before import. The transfer expires after 30 minutes.

Session transfer grants another device access to the saved accounts until their Пульс sessions expire or are revoked. Transfer only to trusted devices and people. Existing identical sessions on the receiver are skipped. Group assignments are included in both transfer methods.

The app sends the QR token to Пульс's `SelfApproveAttendanceThroughQRCode` gRPC-Web method. Пульс may reject an account that is not enrolled in the lecture or whose presence in the campus access system is not recorded. The API is inferred from the Пульс web client as of September 2026; it is not a documented public integration and may change.

## Development

### USB NFC reader diagnostics

On Ubuntu, install `pcscd`, `pcsc-tools`, and `libacsccid1`. The generic `libccid` package does not list the ACR1281 2S CL (`072f:2215`):

```sh
sudo apt update
sudo apt install pcscd pcsc-tools libacsccid1
sudo systemctl enable --now pcscd.socket
sudo systemctl restart pcscd.service
```

Run `python3 tool/nfc_probe.py --watch` and hold a card or a phone with its NFC pass open near the ACR1281 reader. The utility reports reader names, card presence, protocol, and ATR. Press Ctrl+C to stop. It does not send APDUs, read a pass identifier, or save card data. `pcsc_scan` is an independent way to check whether Linux detects the reader and a nearby card.

On the ACR1281 2S CL, the two slots reporting a `MIFARE Plus SAM` ATR are SAM slots, not the phone. To watch the likely contactless slot alone, run `python3 tool/nfc_probe.py --watch --reader '00 01'`. Try a known ordinary contactless card or NFC tag first: detection there confirms the reader and driver can see a nearby target. An empty slot does not by itself show whether the reader's RF field is on, and a phone pass may require a specific application selection before it responds. This utility cannot determine whether a Pulse pass is compatible with the reader.

Android backups are disabled because device-bound secure storage cannot be restored with its original encryption key on another device. Use the app's QR or nearby session transfer when moving accounts between phones.

### Turnstile NFC diagnostics

Settings → Testing → Turnstile signal uses Android 15+ NFC Observe Mode when Android allows it. While the page is open, it shows polling frame type, raw polling bytes, relative timestamp, and the controller's vendor-specific gain reading. When Android rejects Observe Mode, Android 16+ falls back to reporting reader field on/off events without polling bytes. It is a passive diagnostic: it does not send a pass, save frames, or complete an NFC transaction. Android reader mode and iOS do not expose equivalent turnstile polling data to this app. Seeing frames confirms that the phone detected a reader field; it does not reveal the complete turnstile protocol or prove that a Pulse pass will work.

The [Android Observe Mode Demo compatibility table](https://github.com/kormax/android-observe-mode-demo#supported-devices) reports that Pixel 6/7 support ended after Android 15 QPR2. A newer Android version alone does not restore it; the NFC service must report support.

```sh
/home/leo/flutter/bin/flutter pub get
/home/leo/flutter/bin/flutter analyze
/home/leo/flutter/bin/flutter test
/home/leo/flutter/bin/dart run tool/check_translations.dart
/home/leo/flutter/bin/flutter run -d linux
/home/leo/flutter/bin/dart run flutter_launcher_icons
```

Linux is for previewing the UI, testing a pasted QR link, and testing nearby transfer. Browser login and camera scanning are available on Android and iOS. The Linux build requires `libsecret-1-dev` (on Ubuntu: `sudo apt install libsecret-1-dev`) for the secure-storage plugin. An Android SDK and accepted licenses are needed for APK builds. iOS builds require macOS and Xcode. iOS needs local network permission for nearby transfer; the app declares its Bonjour service in `Info.plist`.

`third_party/flutter_inappwebview_android` is the upstream 1.1.3 Android implementation with its two ProGuard defaults changed to `proguard-android-optimize.txt` for Android Gradle Plugin 9.1. Its upstream license is included in that directory.

Launcher icons are generated from `icon/app_icon.png`. The top bar uses `icon/brand.svg`, a copy of the supplied SVG with only unsupported metadata removed.

Android themed icons use `icon/app_icon_monochrome.png`, with an editable vector source in `icon/app_icon_monochrome.svg`. The launcher applies its wallpaper tint when themed icons are enabled. The monochrome layer is included in the `flutter_launcher_icons` configuration and regenerated by the same command above.

### NFC pass queue (Android)

Open the **Passes** tab in the bottom navigation. Enroll each account with the verification code sent to its owner by the pass provider. Pass numbers are stored in Android secure storage and bound to the session that enrolled them; signing in again requires enrolling again. Pass credentials are not included in session transfers. Removing an account also removes its enrolled pass from this app.

Select the enrolled passes to test, set the delay (1–300 seconds; default 60), and choose **Your account** to place your pass at the end. The selection, delay, and your account are saved for subsequent visits. Search the pass list by name when needed. Start the queue and hold the unlocked phone against the gate. After the first NFC response for a pass, the queue waits for the configured delay, then automatically selects the next pass. It waits for a reader command before starting that pass's delay. Repeated commands and taps during the delay keep using the same pass. The gate may require removing and tapping the phone again: the app cannot force the reader to start a new transaction. **Presented** counts phone responses, not admissions or recorded campus presence. Check acceptance at the gate.

The **Passes → Add widget** button offers compact 1×1 and labeled 2×1 NFC widgets. Your launcher confirms placement, or the app directs you to the launcher's widget picker if pinning is unavailable. Tap the NFC widget to open Passes and automatically start your saved queue. An empty selection asks for setup; an explicitly cleared selection never falls back to all passes. Missing or expired enrollment still requires the owner’s verification code. Widgets use the chosen app language for their contents and Android's wallpaper colors on Android 12+, with light and dark variants. The QR widgets use the same theme colors.

Keep the Passes tab open. Switching tabs or opening Settings stops the queue. It keeps the display awake; leaving the app, stopping the queue, finishing it, or expiration of the active pass token stops presentation. Starting obtains a fresh pass token for each selected account. The native queue only holds pass numbers and expiry times in process memory. It requests foreground NFC routing so Pulse can stay installed.

The native protocol was independently implemented from inspection of the installed Pulse 2.1.0+253 APK: AID `F222222222`, variable-length little-endian pass number followed by `9000`. The enrollment client is vendored from the MIT-licensed `/home/leo/university-app` repository, whose private native module is absent. See [NFC findings](docs/nfc-protocol.md) for evidence and test limits. Live enrollment and gate acceptance require testing with the university's accounts and reader.

All local UI strings and known attendance results have Russian, English, French, Portuguese and Simplified Chinese copy. `tool/check_translations.dart` audits literal UI calls and attendance-result messages; the test suite also checks translated placeholders. NFC verification retry dates follow the app language and the phone's clock format.
