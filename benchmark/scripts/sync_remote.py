#!/usr/bin/env python3
"""Sync the benchmark set with the hosted collector (collector/).

The repo stays the source of record; the collector is where photos and labels
accumulate between syncs. Stdlib only.

    # once: seed the remote with the local images + labels
    .venv/bin/python benchmark/scripts/sync_remote.py push

    # after friends upload/label: bring everything home, then review the diff
    .venv/bin/python benchmark/scripts/sync_remote.py pull
    git diff benchmark/labels

Pulled field originals land in menu-pics/field/ (gitignored, like all images);
normalized copies land in benchmark/images/ ready for run_parse.py.

Config via flags or environment:

    export COLLECTOR_URL=https://oshinagaki-collector.<you>.workers.dev
    export COLLECTOR_PASSCODE=...

Conflict policy: pull overwrites local labels (git is the safety net — review
the diff before committing). push never overwrites a remote label that differs,
unless --force-labels; pull first, then push.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import IMAGES_DIR, LABELS_DIR, ROOT  # noqa: E402

FIELD_ORIGINALS_DIR = ROOT.parent / "menu-pics" / "field"


class Remote:
    def __init__(self, url: str, passcode: str):
        self.base = url.rstrip("/")
        self.passcode = passcode

    def _request(self, method: str, path: str, body: bytes | None = None, content_type: str | None = None):
        req = urllib.request.Request(self.base + path, data=body, method=method)
        req.add_header("X-Passcode", self.passcode)
        if content_type:
            req.add_header("Content-Type", content_type)
        return urllib.request.urlopen(req, timeout=120)

    def get_json(self, path: str) -> dict:
        with self._request("GET", path) as r:
            return json.loads(r.read().decode("utf-8"))

    def get_bytes(self, path: str) -> bytes:
        with self._request("GET", path) as r:
            return r.read()

    def put(self, path: str, body: bytes, content_type: str) -> None:
        with self._request("PUT", path, body, content_type) as r:
            r.read()


def md5(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def push(remote: Remote, force_labels: bool, dry_run: bool) -> int:
    manifest = remote.get_json("/api/sync/manifest")
    remote_images = {e["key"]: e for e in manifest["images"]}
    remote_labels = {e["key"]: e for e in manifest["labels"]}

    pushed = skipped = conflicts = 0
    for path in sorted(IMAGES_DIR.glob("*.jpg")):
        entry = remote_images.get(path.name)
        if entry and entry["etag"] == md5(path):
            skipped += 1
            continue
        print(f"push image  {path.name}")
        if not dry_run:
            remote.put(f"/api/sync/image/{path.name}", path.read_bytes(), "image/jpeg")
        pushed += 1

    for path in sorted(LABELS_DIR.glob("*.json")):
        entry = remote_labels.get(path.name)
        if entry and entry["etag"] == md5(path):
            skipped += 1
            continue
        if entry and not force_labels:
            # The remote copy differs — someone may have labeled it there.
            print(f"CONFLICT    {path.name}  (remote differs; pull first, or --force-labels)")
            conflicts += 1
            continue
        print(f"push label  {path.name}")
        if not dry_run:
            remote.put(f"/api/sync/label/{path.name}", path.read_bytes(), "application/json")
        pushed += 1

    print(f"\npushed {pushed}, unchanged {skipped}, conflicts {conflicts}"
          + (" (dry run)" if dry_run else ""))
    return 1 if conflicts else 0


def pull(remote: Remote, with_originals: bool, dry_run: bool) -> int:
    manifest = remote.get_json("/api/sync/manifest")

    changed = new_images = new_originals = unchanged = 0
    for entry in manifest["labels"]:
        local = LABELS_DIR / entry["key"]
        if local.exists() and md5(local) == entry["etag"]:
            unchanged += 1
            continue
        print(f"pull label     {entry['key']}" + ("  (new)" if not local.exists() else "  (changed)"))
        if not dry_run:
            # Raw bytes, so the local md5 matches the remote etag next time.
            body = remote.get_bytes(f"/api/sync/label/{entry['key']}")
            local.parent.mkdir(parents=True, exist_ok=True)
            local.write_bytes(body)
        changed += 1

    for entry in manifest["images"]:
        local = IMAGES_DIR / entry["key"]
        if local.exists():
            unchanged += 1
            continue
        print(f"pull image     {entry['key']}")
        if not dry_run:
            local.parent.mkdir(parents=True, exist_ok=True)
            local.write_bytes(remote.get_bytes(f"/api/image/{entry['key']}"))
        new_images += 1

    if with_originals:
        for entry in manifest["originals"]:
            local = FIELD_ORIGINALS_DIR / entry["key"]
            if local.exists():
                unchanged += 1
                continue
            print(f"pull original  {entry['key']}")
            if not dry_run:
                local.parent.mkdir(parents=True, exist_ok=True)
                stem = Path(entry["key"]).stem
                local.write_bytes(remote.get_bytes(f"/api/original/{stem}"))
            new_originals += 1

    print(f"\nlabels changed {changed}, new images {new_images}, new originals {new_originals}, "
          f"unchanged {unchanged}" + (" (dry run)" if dry_run else ""))
    if changed and not dry_run:
        print("review contributor labels before committing:  git diff benchmark/labels")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["push", "pull"])
    ap.add_argument("--url", default=os.environ.get("COLLECTOR_URL"), help="Collector base URL")
    ap.add_argument("--passcode", default=os.environ.get("COLLECTOR_PASSCODE"))
    ap.add_argument("--force-labels", action="store_true",
                    help="push: overwrite remote labels that differ from local")
    ap.add_argument("--no-originals", action="store_true",
                    help="pull: skip full-resolution originals")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.url or not args.passcode:
        print("error: set --url/--passcode or COLLECTOR_URL/COLLECTOR_PASSCODE", file=sys.stderr)
        return 2

    remote = Remote(args.url, args.passcode)
    try:
        if args.command == "push":
            return push(remote, args.force_labels, args.dry_run)
        return pull(remote, not args.no_originals, args.dry_run)
    except urllib.error.HTTPError as exc:
        print(f"error: {exc.code} {exc.reason} — {exc.read().decode('utf-8', 'replace')[:200]}", file=sys.stderr)
        return 1
    except urllib.error.URLError as exc:
        print(f"error: cannot reach {args.url}: {exc.reason}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
