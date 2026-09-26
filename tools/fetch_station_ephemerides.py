#!/usr/bin/env python3
"""Refresh the bundled ISS/CSS OEM snapshots from their official publishers."""
import datetime as dt
import html
import json
from pathlib import Path
import re
import urllib.request

SOURCES = [
    ("iss", "ISS", "NASA / Roscosmos / ESA / JAXA / CSA",
     "https://nasa-public-data.s3.amazonaws.com/iss-coords/current/ISS_OEM/ISS.OEM_J2K_EPH.txt"),
    ("tiangong", "TIANGONG", "China Manned Space Agency",
     "https://en.cmse.gov.cn/news/202107/t20210722_48418.html"),
]
NUMBER = r"([+-]?\d+\.\d+)"
STATE = re.compile(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+)\s+" + r"\s+".join([NUMBER] * 6))


def fetch_snapshot(identifier, name, operator, url):
    with urllib.request.urlopen(url, timeout=45) as response:
        source = response.read().decode("utf-8")
    source = html.unescape(re.sub(r"<[^>]+>", " ", source))
    if not re.search(r"REF_FRAME\s*=\s*EME2000", source):
        raise ValueError(f"{name}: unsupported coordinate frame")
    if not re.search(r"TIME_SYSTEM\s*=\s*UTC", source):
        raise ValueError(f"{name}: unsupported time system")
    samples = []
    for match in STATE.finditer(source):
        timestamp = dt.datetime.fromisoformat(match[1]).replace(tzinfo=dt.timezone.utc).timestamp()
        values = [float(match[i]) for i in range(2, 8)]
        if samples and timestamp <= samples[-1][0]:
            raise ValueError(f"{name}: unordered or duplicate OEM states")
        radius = sum(x*x for x in values[:3]) ** .5
        if not 6500 < radius < 7500:
            raise ValueError(f"{name}: unexpected low Earth orbit position")
        samples.append([timestamp, *values])
    if len(samples) < 100:
        raise ValueError(f"{name}: incomplete OEM")
    return dict(id=identifier, name=name, operator=operator, source=url,
                frame="EME2000", retrieved_utc=dt.datetime.now(dt.timezone.utc).isoformat(), samples=samples)


if __name__ == "__main__":
    # Fetch and validate both before replacing the last known working bundle.
    rows = [fetch_snapshot(*source) for source in SOURCES]
    target = Path(__file__).resolve().parents[1] / "data/earth_station_ephemerides.json"
    temporary = target.with_suffix(".tmp")
    temporary.write_text(json.dumps(rows, separators=(",", ":")) + "\n")
    temporary.replace(target)
    for row in rows:
        print(row["name"], len(row["samples"]), "dated states")
