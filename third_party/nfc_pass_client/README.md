# Vendored NFC enrollment client

Source: `/home/leo/university-app/packages/nfc_pass_client`, copied 3 October 2026 under the reference repository's MIT license (included as `LICENSE`). The Dart library and generated protobuf files are unchanged; package workspace resolution and development-only dependencies were removed for standalone path use.

The reference project's private native HCE module is not included. This package only provides enrollment transport, verification decoding and its original optional platform-channel wrapper. AntiAttendance uses its own native queue channel.
