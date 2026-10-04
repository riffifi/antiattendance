# Pulse NFC findings

Inspected on 3 October 2026 using the connected Pixel 7. Package: `ru.mirea.pulse`; installed version: `2.1.0+253` (version code 253).

APK SHA-256: `89ff7c37dd30ffc8ab24b228c56e898b3de90908a5706bb3a98abc4d1c275791`.

The APK and decompiler output are local investigation artifacts in `/tmp/antiattendance-pulse-inspect`, outside the repository. Only installed application code/resources were inspected; no Pulse account storage, pass identifiers, access tokens, or verification codes were extracted. No production enrollment or gate transactions were performed during this inspection.

## Native protocol

The installed manifest registers `ru.mirea.pulse.presentation.service.DigitalPassHostApduService` with `android.permission.BIND_NFC_SERVICE`.

`res/xml/apduservice.xml` requires device unlock and registers `F222222222` in category `other`.

The service's `processCommandApdu` loads `digital_pass` as an Android `long`. It returns no response when the identifier is zero or the repository reports an invalid token. Otherwise, it converts the long to hexadecimal, decodes it with `G3.AbstractC0217i0.b(string, true)`, and appends status bytes `90 00`. That helper pads odd-length hexadecimal to an even length, decodes pairs, then reverses the bytes when its boolean argument is true. This is a variable-length unsigned little-endian representation of a positive pass number, not an eight-byte padded integer.

Examples with synthetic values:

| Decimal pass number | Response bytes |
| --- | --- |
| 1 | `01 90 00` |
| 2748 | `BC 0A 90 00` |
| 65535 | `FF FF 90 00` |

Pulse does not branch on the APDU command contents in this service. Its `onDeactivated` is empty. It opens an overlay with `success_key` reflecting whether a pass response was constructed; this is not an acknowledgment from the gate.

`p145p8.h.d()` requires a saved `access_token` and a future `expiration_time`. The new app obtains its own token through the authenticated enrollment API and enforces its JWT expiry. It does not import Pulse's token or pass.

JADX fully recovered the relevant service, conversion helper, repository validity check, and AID resource. Full-app decompilation reported errors in 98 other methods/classes; this is not a claim that every part of the APK was reconstructed.

## Enrollment and lifecycle APIs

The public reference repository supplies the protobuf schema, gRPC-Web transport, verification outcomes and cookie handling for:

- `/rtu.pulse_app.LongTimeTokenService/GetAccessTokenForDigitalPass`
- `/rtu_tc.rtu_attend.humanpass.HumanPassService/SendVerificationCode`
- `/rtu_tc.rtu_attend.humanpass.HumanPassService/GetDigitalPass`

The installed APK also calls `GetDigitalPassStatus`. The response has outcomes `no_digital_pass` (field 1), `digital_pass_available` (field 2), and `using_digital_pass_info` (field 3). The latter includes `usage_id` (field 1), `device_info` (field 2), and `in_use_since` (field 3). Pulse compares this usage ID with the `using_id` returned during enrollment. This app does not currently implement that remote binding-status check; a fresh access token alone does not prove the pass remains valid. The gate can reject a revoked or replaced pass.

The vendored client retains the upstream MIT license. No decompiled Pulse source was copied into the app. The Android response encoder and queue were implemented independently.

## Queue behavior and validation limits

Android HCE responds to reader commands; it cannot initiate a transaction or force another selection. The configurable cooldown is a test setting, not a timeout extracted from Pulse. Queue advancement starts with the first response, uses monotonic time, and does not restart on repeat commands or RF link loss. After the delay, the next reader command receives the next pass. A new pass waits indefinitely until the reader addresses it. Choosing the user's own account preserves the other accounts' order and puts that account last.

Foreground routing is requested with `CardEmulation.setPreferredService`; the campus AID is dynamically registered when the queue starts and removed on stop. The static standby AID `F0416E746950617373` is separate from Pulse's campus AID. The service refuses pass responses while the queue is stopped. The queue is cleared when the activity pauses. On a fresh activity or stopped service creation, stale dynamic registrations are removed. The phone screen stays awake while the queue runs.

Automated tests cover byte order/length, repeated commands, no-command waiting, cooldown advancement, token expiration, stopped-queue refusal, own-account ordering and secure session binding. The connected Pixel reports `android.hardware.nfc.hce`. End-to-end enrollment, RF exchanges, the actual gate cooldown and gate acceptance remain unverified.

Android HCE behavior is documented in the [Android host card emulation guide](https://developer.android.com/develop/connectivity/nfc/hce).
