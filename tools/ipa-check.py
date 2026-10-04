#!/usr/bin/env python3
"""Fertige Dopa-IPA durchleuchten (ohne Mac): Info.plists, Dateien der Widget-Erweiterung,
Plattform/SDK aus dem Mach-O, Entitlements und Signatur-ID aus der ldid-Signatur.

    python3 tools/ipa-check.py /var/www/momentum/releases/Dopa-48.ipa
"""
import plistlib
import struct
import sys
import zipfile

LC_BUILD_VERSION = 0x32
LC_CODE_SIGNATURE = 0x1D
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018


def version(x):
    return f"{x >> 16}.{(x >> 8) & 0xff}.{x & 0xff}"


def macho(ipa, path):
    data = ipa.read(path)
    magic = struct.unpack("<I", data[:4])[0]
    print("=====", path, "magic", hex(magic), "size", len(data))
    if magic != 0xFEEDFACF:
        print("  (fat oder anderes Format)")
        return data
    ncmds = struct.unpack("<I", data[16:20])[0]
    off = 32
    libs = []
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", data[off:off + 8])
        if cmd == LC_BUILD_VERSION:
            platform, minos, sdk = struct.unpack("<III", data[off + 8:off + 20])
            print(f"  LC_BUILD_VERSION platform={platform} minos={version(minos)} sdk={version(sdk)}")
        elif cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
            name_off = struct.unpack("<I", data[off + 8:off + 12])[0]
            name = data[off + name_off:off + size].split(b"\x00")[0].decode()
            libs.append(("weak " if cmd == LC_LOAD_WEAK_DYLIB else "") + name.split("/")[-1])
        elif cmd == LC_CODE_SIGNATURE:
            sig_off, sig_size = struct.unpack("<II", data[off + 8:off + 16])
            blob = data[sig_off:sig_off + sig_size]
            start = blob.find(b"<?xml")
            if start >= 0:
                end = blob.find(b"</plist>", start)
                print("  Entitlements:", plistlib.loads(blob[start:end + 8]))
            cd = blob.find(b"\xfa\xde\x0c\x02")
            if cd >= 0:
                ident_off = struct.unpack(">I", blob[cd + 20:cd + 24])[0]
                ident = blob[cd + ident_off:blob.find(b"\x00", cd + ident_off)]
                print("  Signatur-ID:", ident.decode())
        off += size
    print("  Bibliotheken:", ", ".join(libs))
    return data


def main(path):
    ipa = zipfile.ZipFile(path)
    names = ipa.namelist()
    app = "Payload/Dopa.app/"
    ext = app + "PlugIns/DopaWidget.appex/"

    for label, plist in [("APP", app + "Info.plist"), ("EXT", ext + "Info.plist")]:
        print("=====", label, plist)
        p = plistlib.loads(ipa.read(plist))
        for k in sorted(p):
            print(f"  {k}: {p[k]!r}"[:240])

    print("===== Dateien in der Erweiterung")
    for n in names:
        if n.startswith(ext) and n.count("/") <= 4:
            print(" ", n[len(ext):], ipa.getinfo(n).file_size)

    macho(ipa, app + "Dopa")
    ext_bin = macho(ipa, ext + "DopaWidget")
    for needle in [b"DopaTimerAttributes", b"ActivityConfiguration", b"ActivityKit"]:
        print("  enthält", needle.decode(), needle in ext_bin)


if __name__ == "__main__":
    main(sys.argv[1])
