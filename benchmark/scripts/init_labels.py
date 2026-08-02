#!/usr/bin/env python3
"""Create a ground-truth label stub for every normalized image.

Existing label files are never overwritten, so this is safe to re-run after
adding photos. Fill in `attributes` and `sections` by hand, then set
`"labeled": true` — score.py ignores anything still marked false.

    python3 benchmark/scripts/init_labels.py
    python3 benchmark/scripts/init_labels.py --provenance field
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import IMAGES_DIR, LABELS_DIR, write_json  # noqa: E402


def stub(image: str, source_file: str, provenance: str) -> dict:
    return {
        "image": image,
        "source_file": source_file,
        "labeled": False,
        "attributes": {
            "provenance": provenance,
            "orientation": None,
            "script": None,
            "surface": None,
            "lighting": None,
            "angle": None,
            "blur": None,
            "columns": None,
        },
        "sections": [{"header_ja": None, "items": []}],
        "decorative_text": [],
        "notes": "",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "--provenance",
        choices=["web", "field"],
        default="web",
        help="How these images were obtained. 'field' = you photographed them in a real "
        "venue. The scorer reports the two separately (default: web)",
    )
    args = ap.parse_args()

    manifest_path = IMAGES_DIR / "manifest.json"
    if not manifest_path.exists():
        print("error: no manifest. Run normalize.py first.", file=sys.stderr)
        return 1

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    LABELS_DIR.mkdir(parents=True, exist_ok=True)

    created = existing = 0
    for entry in manifest["images"]:
        path = LABELS_DIR / f"{Path(entry['image']).stem}.json"
        if path.exists():
            existing += 1
            continue
        write_json(path, stub(entry["image"], entry["source_file"], args.provenance))
        created += 1

    print(f"created {created} label stub(s), left {existing} existing file(s) alone -> {LABELS_DIR}")
    if created:
        print("\nNext: open each file, fill in attributes + sections, set \"labeled\": true.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
