#!/usr/bin/env python3
"""Normalize source menu photos into a consistent benchmark set.

Every image becomes a JPEG at a fixed maximum long edge, so format and
resolution are never confounding variables when comparing models. Benchmark at
the resolution you will actually ship: a phone upload is downscaled before it
reaches the API, and measuring against 4000px originals gives you cost and
accuracy numbers that no real user will ever see.

    python3 benchmark/scripts/normalize.py ../menu-pics
    python3 benchmark/scripts/normalize.py ../menu-pics --max-dim 2576 --suffix hi
"""

from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from pathlib import Path

from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import IMAGES_DIR, write_json  # noqa: E402

SOURCE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".avif", ".heic", ".heif", ".tif", ".tiff", ".bmp", ".gif"}


def slugify(name: str) -> str:
    """ASCII-safe, stable stem. Japanese filenames become their hex digest tail."""
    stem = unicodedata.normalize("NFKC", Path(name).stem)
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", stem).strip("-").lower()
    slug = re.sub(r"-{2,}", "-", slug)
    if not slug:
        import hashlib

        slug = "img-" + hashlib.sha1(name.encode("utf-8")).hexdigest()[:10]
    return slug[:60]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", type=Path, help="Directory of source images")
    ap.add_argument(
        "--max-dim",
        type=int,
        default=1568,
        help="Max long edge in px. 1568 is the standard vision tier; 2576 is the "
        "high-resolution ceiling on Opus 5 / Sonnet 5 and costs up to ~3x the "
        "image tokens (default: 1568)",
    )
    ap.add_argument("--quality", type=int, default=88, help="JPEG quality (default: 88)")
    ap.add_argument("--suffix", default="", help="Append to output filenames, for resolution sweeps")
    ap.add_argument("--out", type=Path, default=IMAGES_DIR)
    args = ap.parse_args()

    source = args.source.expanduser().resolve()
    if not source.is_dir():
        print(f"error: {source} is not a directory", file=sys.stderr)
        return 1

    args.out.mkdir(parents=True, exist_ok=True)
    manifest, skipped, seen = [], [], set()

    for path in sorted(source.iterdir()):
        if not path.is_file() or path.suffix.lower() not in SOURCE_EXTS:
            continue
        try:
            with Image.open(path) as im:
                # Honour EXIF orientation before measuring — a portrait phone
                # photo stored as landscape-plus-a-rotation-flag would otherwise
                # be resized along the wrong axis.
                im = ImageOps.exif_transpose(im)
                orig_w, orig_h = im.size
                im = im.convert("RGB")
                im.thumbnail((args.max_dim, args.max_dim), Image.LANCZOS)

                stem = slugify(path.name)
                if args.suffix:
                    stem = f"{stem}-{args.suffix}"
                n = 2
                base = stem
                while stem in seen:
                    stem = f"{base}-{n}"
                    n += 1
                seen.add(stem)

                out_path = args.out / f"{stem}.jpg"
                im.save(out_path, "JPEG", quality=args.quality, optimize=True)
                manifest.append(
                    {
                        "image": out_path.name,
                        "source_file": path.name,
                        "original_size": [orig_w, orig_h],
                        "normalized_size": list(im.size),
                        "bytes": out_path.stat().st_size,
                    }
                )
        except Exception as exc:  # noqa: BLE001 - report and continue the batch
            skipped.append({"source_file": path.name, "error": f"{type(exc).__name__}: {exc}"})

    write_json(args.out / "manifest.json", {"max_dim": args.max_dim, "images": manifest, "skipped": skipped})

    print(f"normalized {len(manifest)} image(s) -> {args.out} (max long edge {args.max_dim}px)")
    if skipped:
        print(f"skipped {len(skipped)}:", file=sys.stderr)
        for s in skipped:
            print(f"  {s['source_file']}: {s['error']}", file=sys.stderr)
        print(
            "\n(.avif and .heic need extra decoders: pip install pillow-avif-plugin pillow-heif)",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
