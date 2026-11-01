#!/usr/bin/env python3
"""Publish HOS 150 unsigned IPA as a free SideStore / AltStore app source."""
from pathlib import Path
from zipfile import ZipFile
import datetime as dt
import json, math, plistlib, struct, sys, zlib

BASE = "https://raw.githubusercontent.com/ddsheppard1984/-Hos-150-air-mile/hos150-ios-updates/ota/"
BUNDLE = "com.houseofsqueak.hos150"

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind+data) & 0xffffffff)

def icon(path):
    n=128
    rows=bytearray()
    for y in range(n):
        rows.append(0)
        for x in range(n):
            in_body = (12<x<116 and 43<y<92)
            cab = (x>70 and x<112 and y>31 and y<90)
            tire = (((x-34)**2+(y-95)**2)<110 or ((x-94)**2+(y-95)**2)<110)
            win = 80<x<102 and 40<y<60
            rgb=(41,212,176) if in_body or cab else (12,26,45)
            if tire: rgb=(233,246,247)
            if win: rgb=(21,61,91)
            rows.extend(rgb)
    head=struct.pack(">IIBBBBB",n,n,8,2,0,0,0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",head)+chunk(b"IDAT",zlib.compress(bytes(rows),9))+chunk(b"IEND",b""))

def main(ipa_name, outdir):
    ipa=Path(ipa_name)
    out=Path(outdir)
    out.mkdir(parents=True,exist_ok=True)
    with ZipFile(ipa) as z:
        assert z.testzip() is None, "Corrupt unsigned IPA"
        info=plistlib.loads(z.read("Payload/HOS150.app/Info.plist"))
    assert info["CFBundleIdentifier"] == BUNDLE
    version=str(info["CFBundleShortVersionString"])
    build=str(info["CFBundleVersion"])
    assert version == "1.0.2" and int(build)>100, (version,build)
    (out/"HOS150.ipa").write_bytes(ipa.read_bytes())
    __import__("shutil").copyfile("ios/HOS150/Assets.xcassets/AppIcon.appiconset/AppIcon.png",out/"icon.png")
    date=dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    source={
        "name":"House of Squeak — HOS 150",
        "identifier":"com.houseofsqueak.hos150.altstore",
        "sourceURL":BASE+"source.json",
        "description":"Free HOS 150 native iPhone app updates",
        "iconURL":BASE+"icon.png",
        "tintColor":"29D4B0",
        "apps":[{
            "name":"HOS 150",
            "bundleIdentifier":BUNDLE,
            "developerName":"House of Squeak",
            "subtitle":"Driver dashboard • GPS tools • HOS 150",
            "localizedDescription":"Native iPhone wrapper for the privately hosted HOS 150 driver app, including secure Cloudflare email login and optional native GPS telemetry. Prototype only — NOT a certified ELD. Never interact while driving.",
            "iconURL":BASE+"icon.png",
            "category":"utilities",
            "versions":[{
                "version":version,
                "buildVersion":build,
                "date":date,
                "localizedDescription":"Optional Face ID app lock, native HOS alerts and clearer driver pages",
                "downloadURL":BASE+"HOS150.ipa",
                "size":ipa.stat().st_size,
                "minOSVersion":"17.0"
            }]
        }],
        "news":[]
    }
    (out/"source.json").write_text(json.dumps(source,indent=2)+"\n")
    print("PUBLISHED SOURCE:",BASE+"source.json","VERSION",version,"BUILD",build)

if __name__ == "__main__":
    if len(sys.argv)!=3: raise SystemExit("Usage: ota_publish.py input.ipa output_dir")
    main(sys.argv[1],sys.argv[2])
