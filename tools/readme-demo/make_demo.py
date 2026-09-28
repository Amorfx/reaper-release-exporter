#!/usr/bin/env python3
"""Builds the demo projects used for the README screenshots (see README.md in this folder).

Writes out/demo.rpp (5 songs, one excluded), out/demo-invalid.rpp (bad ISRC on song 3),
out/demo-empty.rpp (items without regions), out/Media/tone-3s.wav and out/cover.jpg.
"""
import json
import os
import shutil
import subprocess
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
TONE = os.path.join(HERE, "..", "fixtures", "tone-3s.wav")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

SONGS = [  # title, seconds, artist, isrc, composer, include
    ("Prelude in Blue", 168, "", "FRZ032600101", "É. Moreau", True),
    ("Night Drive", 222, "Élise Moreau feat. Sam Keller", "FRZ032600102", "É. Moreau, S. Keller", True),
    ("Paper Lanterns", 245, "", "FRZ032600103", "É. Moreau", True),
    ("Glasshouse", 201, "", "FRZ032600104", "É. Moreau", True),
    ("Voice memo (demo)", 72, "", "", "", False),
]
RELEASE = {"artist": "Élise Moreau", "album_artist": "", "album": "Night Songs", "year": "2026-10-17",
           "genre": "Neoclassical", "label": "Quiet Room Records", "copyright": "(P) 2026 Élise Moreau",
           "cover": os.path.join(OUT, "cover.jpg")}
# A neutral folder, so no user name shows up in the screenshots.
SETTINGS = {"output_dir": "/Users/Shared/Releases/Night Songs", "pattern": "{nn} - {title}",
            "primary": "wav24", "secondary": "mp3_320", "srate": 0}


def guid():
    return "{%s}" % str(uuid.uuid4()).upper()


def read_lines(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read().rstrip("\n").split("\n")


def item(pos, length, name):
    return ["    <ITEM", f"      POSITION {pos}", "      SNAPOFFS 0", f"      LENGTH {length}", "      LOOP 1",
            "      ALLTAKES 0", "      FADEIN 1 0 0 1 0 0 0", "      FADEOUT 1 0 0 1 0 0 0", "      MUTE 0 0",
            "      SEL 1", f"      IGUID {guid()}", "      IID 1", f"      NAME {name}", "      VOLPAN 1 0 1 -1",
            "      SOFFS 0", "      PLAYRATE 1 1 0 -1 0 0.0025", "      CHANMODE 0", f"      GUID {guid()}",
            "      <SOURCE WAVE", '        FILE "Media/tone-3s.wav"', "      >", "    >"]


def project(region_guids, with_regions, with_data, isrc_override=None):
    track = read_lines("track.rpp")
    track_guid = guid()
    track[0] = "  <TRACK " + track_guid
    track = [line.replace(line.split()[-1], track_guid) if line.startswith("    TRACKID") else line for line in track]
    track.insert(1, "    NAME Masters")
    lines, items, markers, pos = read_lines("header.rpp"), [], [], 1.0
    for n, (title, secs, *_rest) in enumerate(SONGS, 1):
        items += item(pos, secs, title)
        if with_regions:
            markers += [f'  MARKER {n} {pos} "{title}" 1 0 1 B {region_guids[n - 1]} 0 1', f'  MARKER {n} {pos + secs} "" 1']
        pos += secs + 4
    lines += markers + ["  <PROJBAY", "  >"] + track + items + ["  >"]
    if with_data:
        lines += ["  <EXTSTATE", "    <RELEASEEXPORTER", "      EP '%s'" % json.dumps(RELEASE, ensure_ascii=False),
                  "      SCHEMA_VERSION 1", "      SETTINGS '%s'" % json.dumps(SETTINGS)]
        for n, (_title, _secs, artist, isrc, composer, include) in enumerate(SONGS, 1):
            data = {"include": include, "artist": artist, "isrc": (isrc_override or {}).get(n, isrc),
                    "composer": composer}
            lines.append("      TRACK:%s '%s'" % (region_guids[n - 1], json.dumps(data, ensure_ascii=False)))
        lines += ["    >", "  >"]
    return "\n".join(lines + [">"]) + "\n"


def cover():
    png = os.path.join(OUT, "cover.png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--window-size=1400,1400", f"--screenshot={png}", os.path.join(HERE, "cover.html")],
                   check=True, capture_output=True)
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "88", png,
                    "--out", os.path.join(OUT, "cover.jpg")], check=True, capture_output=True)
    os.remove(png)


def main():
    os.makedirs(os.path.join(OUT, "Media"), exist_ok=True)
    shutil.copy(TONE, os.path.join(OUT, "Media", "tone-3s.wav"))
    region_guids = [guid() for _ in SONGS]
    for name, text in [("demo.rpp", project(region_guids, True, True)),
                       ("demo-invalid.rpp", project(region_guids, True, True, {3: "FRZ0326"})),
                       ("demo-empty.rpp", project(region_guids, False, False))]:
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write(text)
    cover()
    print("Demo projects written to", OUT)


if __name__ == "__main__":
    main()
