#!/usr/bin/env python3
"""Web UI for labeling the benchmark set. Stdlib only — no dependencies.

    python3 benchmark/labeling/server.py            # http://localhost:8788
    python3 benchmark/labeling/server.py --port 9000

Labels are written straight into benchmark/labels/, so there is no separate
database and nothing to export: finish a session, `git diff benchmark/labels`,
commit.

To let friends label remotely, expose the port with a tunnel, e.g.:

    cloudflared tunnel --url http://localhost:8788        # or: tailscale funnel 8788

Anyone with the URL can read the images and write labels. The images are
third-party menu photos, so share the link privately and take it down when the
session ends. Labels written by contributors carry their name in `labeled_by`
and stay `verified: false` until you check them in the Review tab.
"""

from __future__ import annotations

import argparse
import json
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent
IMAGES_DIR = BENCH / "images"
LABELS_DIR = BENCH / "labels"

CLAIM_TTL_S = 30 * 60

_lock = threading.Lock()
_claims: dict[str, tuple[str, float]] = {}  # stem -> (labeler, claimed_at)

SAFE_STEM = re.compile(r"^[a-zA-Z0-9._-]+$")


def _label_path(stem: str) -> Path | None:
    if not SAFE_STEM.match(stem):
        return None
    return LABELS_DIR / f"{stem}.json"


def _load_label(stem: str) -> dict | None:
    path = _label_path(stem)
    if path is None or not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def _save_label(stem: str, data: dict) -> None:
    path = _label_path(stem)
    if path is None:
        raise ValueError("bad stem")
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def _active_claims() -> dict[str, str]:
    now = time.time()
    with _lock:
        expired = [s for s, (_, ts) in _claims.items() if now - ts > CLAIM_TTL_S]
        for s in expired:
            del _claims[s]
        return {s: name for s, (name, _) in _claims.items()}


def _state() -> dict:
    claims = _active_claims()
    rows = []
    for path in sorted(LABELS_DIR.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        stem = path.stem
        item_count = sum(len(s.get("items") or []) for s in data.get("sections") or [])
        rows.append(
            {
                "stem": stem,
                "image": data.get("image"),
                "labeled": bool(data.get("labeled")),
                "verified": bool(data.get("verified")),
                "labeled_by": data.get("labeled_by"),
                "provenance": (data.get("attributes") or {}).get("provenance"),
                "item_count": item_count,
                "claimed_by": claims.get(stem),
            }
        )
    return {
        "images": rows,
        "counts": {
            "total": len(rows),
            "labeled": sum(1 for r in rows if r["labeled"]),
            "verified": sum(1 for r in rows if r["verified"]),
        },
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # --- plumbing -----------------------------------------------------------

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, data, code: int = 200) -> None:
        self._send(code, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > 5_000_000:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except json.JSONDecodeError:
            return {}

    def log_message(self, fmt, *args):  # quiet
        pass

    # --- routes -------------------------------------------------------------

    def do_GET(self) -> None:
        if self.path in ("/", "/index.html"):
            page = (HERE / "index.html").read_bytes()
            self._send(200, page, "text/html; charset=utf-8")
        elif self.path == "/api/state":
            self._json(_state())
        elif self.path.startswith("/api/label/"):
            stem = self.path.rsplit("/", 1)[-1]
            label = _load_label(stem)
            if label is None:
                self._json({"error": "not found"}, 404)
            else:
                self._json(label)
        elif self.path.startswith("/images/"):
            name = self.path.rsplit("/", 1)[-1]
            if not SAFE_STEM.match(name) or not name.endswith(".jpg"):
                self._json({"error": "bad name"}, 400)
                return
            path = IMAGES_DIR / name
            if not path.exists():
                self._json({"error": "not found"}, 404)
                return
            self._send(200, path.read_bytes(), "image/jpeg")
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:
        body = self._read_body()
        labeler = (body.get("labeler") or "").strip()[:60]

        if self.path == "/api/claim":
            if not labeler:
                self._json({"error": "name required"}, 400)
                return
            claims = _active_claims()
            for row in _state()["images"]:
                if row["labeled"] or row["stem"] in claims:
                    continue
                with _lock:
                    _claims[row["stem"]] = (labeler, time.time())
                self._json({"stem": row["stem"]})
                return
            self._json({"stem": None})

        elif self.path == "/api/release":
            stem = body.get("stem") or ""
            with _lock:
                _claims.pop(stem, None)
            self._json({"ok": True})

        elif self.path.startswith("/api/label/"):
            stem = self.path.rsplit("/", 1)[-1]
            existing = _load_label(stem)
            if existing is None:
                self._json({"error": "not found"}, 404)
                return
            label = body.get("label")
            if not isinstance(label, dict) or not isinstance(label.get("sections"), list):
                self._json({"error": "label with sections[] required"}, 400)
                return
            # Preserve identity fields; the client edits content, not identity.
            label["image"] = existing["image"]
            label["source_file"] = existing["source_file"]
            label["labeled"] = True
            label["labeled_by"] = labeler or existing.get("labeled_by")
            # Any content edit invalidates prior verification.
            label["verified"] = False
            _save_label(stem, label)
            with _lock:
                _claims.pop(stem, None)
            self._json({"ok": True})

        elif self.path.startswith("/api/verify/"):
            stem = self.path.rsplit("/", 1)[-1]
            existing = _load_label(stem)
            if existing is None:
                self._json({"error": "not found"}, 404)
                return
            existing["verified"] = bool(body.get("verified"))
            _save_label(stem, existing)
            self._json({"ok": True})

        else:
            self._json({"error": "not found"}, 404)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8788)
    ap.add_argument("--host", default="127.0.0.1", help="Bind address (default: 127.0.0.1; tunnels connect locally)")
    args = ap.parse_args()

    if not IMAGES_DIR.exists() or not LABELS_DIR.exists():
        print("error: run normalize.py and init_labels.py first")
        return 1

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"labeling tool: http://{args.host}:{args.port}")
    print("share remotely:  cloudflared tunnel --url http://localhost:%d" % args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
