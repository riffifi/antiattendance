#!/usr/bin/env python3
"""Show USB and PC/SC metadata for a card or phone near the ACR1281 reader.

This tool does not transmit APDUs, read card identifiers, or save card data.
It needs pcscd and a CCID driver to report card status and ATR.
"""

import argparse
import ctypes
import ctypes.util
import sys
import time
from pathlib import Path


VENDOR_ID = "072f"
PRODUCT_ID = "2215"
SCARD_SCOPE_SYSTEM = 2
SCARD_SHARE_SHARED = 2
SCARD_PROTOCOL_T0 = 1
SCARD_PROTOCOL_T1 = 2
SCARD_LEAVE_CARD = 0
SCARD_E_NO_SMARTCARD = 0x8010000C
SCARD_E_NO_READERS_AVAILABLE = 0x8010002E
SCARD_E_NO_SERVICE = 0x8010001D
SAM_ATR_LABEL = b"MIFARE Plus SAM"


def slot_label(reader, atr=""):
    """Describe the observed slot without treating a SAM as an NFC phone."""
    if SAM_ATR_LABEL.hex().upper() in atr.replace(" ", ""):
        return "SAM slot (not the contactless phone/pass)"
    if reader.endswith("00 01") and "ACR1281 2S CL" in reader:
        return "likely contactless slot"
    return "card/phone"


def usb_readers():
    """Find the expected USB device without requiring extra Python packages."""
    for device in Path("/sys/bus/usb/devices").glob("*"):
        try:
            if (device / "idVendor").read_text().strip().lower() != VENDOR_ID:
                continue
            if (device / "idProduct").read_text().strip().lower() != PRODUCT_ID:
                continue
            name = (device / "product").read_text().strip()
            yield f"{name} ({device.name}, USB {VENDOR_ID}:{PRODUCT_ID})"
        except (OSError, UnicodeError):
            continue


class PcscError(Exception):
    def __init__(self, operation, code, library):
        self.code = code & 0xFFFFFFFF
        description = library.pcsc_stringify_error(code)
        detail = description.decode(errors="replace") if description else "Unknown error"
        super().__init__(f"{operation}: {detail} (0x{self.code:08X})")


class Pcsc:
    def __init__(self):
        library_name = ctypes.util.find_library("pcsclite")
        if library_name is None:
            raise RuntimeError("libpcsclite is not installed")
        self.lib = ctypes.CDLL(library_name)
        long = ctypes.c_long
        dword = ctypes.c_ulong
        self.lib.pcsc_stringify_error.argtypes = [long]
        self.lib.pcsc_stringify_error.restype = ctypes.c_char_p
        self.lib.SCardEstablishContext.argtypes = [
            dword, ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(long)
        ]
        self.lib.SCardEstablishContext.restype = long
        self.lib.SCardReleaseContext.argtypes = [long]
        self.lib.SCardReleaseContext.restype = long
        self.lib.SCardListReaders.argtypes = [
            long, ctypes.c_char_p, ctypes.c_void_p, ctypes.POINTER(dword)
        ]
        self.lib.SCardListReaders.restype = long
        self.lib.SCardConnect.argtypes = [
            long, ctypes.c_char_p, dword, dword,
            ctypes.POINTER(long), ctypes.POINTER(dword),
        ]
        self.lib.SCardConnect.restype = long
        self.lib.SCardStatus.argtypes = [
            long, ctypes.c_void_p, ctypes.POINTER(dword),
            ctypes.POINTER(dword), ctypes.POINTER(dword),
            ctypes.c_void_p, ctypes.POINTER(dword),
        ]
        self.lib.SCardStatus.restype = long
        self.lib.SCardDisconnect.argtypes = [long, dword]
        self.lib.SCardDisconnect.restype = long
        self.context = long()
        self._check(
            "SCardEstablishContext",
            self.lib.SCardEstablishContext(
                SCARD_SCOPE_SYSTEM, None, None, ctypes.byref(self.context)
            ),
        )

    def _check(self, operation, result):
        if result:
            raise PcscError(operation, result, self.lib)

    def close(self):
        if self.context.value:
            self.lib.SCardReleaseContext(self.context)
            self.context.value = 0

    def readers(self):
        length = ctypes.c_ulong()
        result = self.lib.SCardListReaders(self.context, None, None, ctypes.byref(length))
        if result & 0xFFFFFFFF == SCARD_E_NO_READERS_AVAILABLE:
            return []
        self._check("SCardListReaders", result)
        buffer = ctypes.create_string_buffer(length.value)
        self._check(
            "SCardListReaders",
            self.lib.SCardListReaders(
                self.context, None, buffer, ctypes.byref(length)
            ),
        )
        return [name.decode(errors="replace") for name in buffer.raw.split(b"\0") if name]

    def card_status(self, reader):
        card = ctypes.c_long()
        protocol = ctypes.c_ulong()
        result = self.lib.SCardConnect(
            self.context,
            reader.encode(),
            SCARD_SHARE_SHARED,
            SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1,
            ctypes.byref(card),
            ctypes.byref(protocol),
        )
        if result & 0xFFFFFFFF == SCARD_E_NO_SMARTCARD:
            return None
        self._check("SCardConnect", result)
        try:
            reader_name = ctypes.create_string_buffer(256)
            name_length = ctypes.c_ulong(len(reader_name))
            state = ctypes.c_ulong()
            atr = ctypes.create_string_buffer(64)
            atr_length = ctypes.c_ulong(len(atr))
            self._check(
                "SCardStatus",
                self.lib.SCardStatus(
                    card,
                    reader_name,
                    ctypes.byref(name_length),
                    ctypes.byref(state),
                    ctypes.byref(protocol),
                    atr,
                    ctypes.byref(atr_length),
                ),
            )
            return (
                "T=0" if protocol.value == SCARD_PROTOCOL_T0 else
                "T=1" if protocol.value == SCARD_PROTOCOL_T1 else
                f"0x{protocol.value:X}",
                bytes(atr.raw[:atr_length.value]).hex(" ").upper(),
            )
        finally:
            self.lib.SCardDisconnect(card, SCARD_LEAVE_CARD)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--watch", action="store_true", help="wait for a card or phone until Ctrl+C")
    parser.add_argument("--reader", help="use only readers containing this text")
    args = parser.parse_args()

    usb = list(usb_readers())
    for name in usb:
        print(f"USB: {name}")
    if not usb:
        print(f"USB: no {VENDOR_ID}:{PRODUCT_ID} reader detected")

    try:
        pcsc = Pcsc()
    except (RuntimeError, OSError, PcscError) as error:
        print(f"PC/SC: {error}", file=sys.stderr)
        print("Install pcscd and libccid, then start pcscd.socket.", file=sys.stderr)
        return 2

    try:
        readers = pcsc.readers()
        if args.reader:
            readers = [name for name in readers if args.reader.lower() in name.lower()]
        if not readers:
            print("PC/SC: no matching readers.")
            if usb:
                print("For USB 072f:2215, install libacsccid1 and restart pcscd.service.")
            else:
                print("Check pcscd, the reader driver, and the USB connection.")
            return 1
        for name in readers:
            print(f"PC/SC reader: {name}")
        last = {}
        while True:
            for name in readers:
                try:
                    status = pcsc.card_status(name)
                except PcscError as error:
                    print(f"{name}: {error}", file=sys.stderr)
                    status = None
                if status == last.get(name) and name in last:
                    continue
                last[name] = status
                if status is None:
                    label = slot_label(name)
                    print(f"{name}: no card detected ({label})")
                else:
                    protocol, atr = status
                    label = slot_label(name, atr)
                    print(f"{name}: {label} present; protocol {protocol}; ATR {atr or '(none)'}")
            if not args.watch:
                break
            time.sleep(0.1)
        return 0
    except KeyboardInterrupt:
        print("\nStopped.")
        return 0
    except PcscError as error:
        print(f"PC/SC: {error}", file=sys.stderr)
        return 1
    finally:
        pcsc.close()


if __name__ == "__main__":
    sys.exit(main())
