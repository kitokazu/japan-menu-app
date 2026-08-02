"""Shared helpers for the parse benchmark."""

from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IMAGES_DIR = ROOT / "images"
LABELS_DIR = ROOT / "labels"
RESULTS_DIR = ROOT / "results"
PROMPTS_DIR = ROOT / "prompts"

# Anthropic first-party pricing, USD per million tokens.
# Sonnet 5 is at introductory pricing through 2026-08-31 ($3/$15 after).
PRICING = {
    "claude-opus-5": (5.00, 25.00),
    "claude-sonnet-5": (2.00, 10.00),
    "claude-haiku-4-5": (1.00, 5.00),
    "claude-opus-4-8": (5.00, 25.00),
}


def cost_usd(model: str, usage: dict) -> float | None:
    """Cost of one request. Cache reads are ~0.1x input, writes ~1.25x."""
    if model not in PRICING:
        return None
    inp, out = PRICING[model]
    per_m = 1_000_000
    total = usage.get("input_tokens", 0) * inp / per_m
    total += usage.get("output_tokens", 0) * out / per_m
    total += usage.get("cache_read_input_tokens", 0) * inp * 0.1 / per_m
    total += usage.get("cache_creation_input_tokens", 0) * inp * 1.25 / per_m
    return total


# Characters that carry no identity for a dish name: whitespace of any width,
# middle dots, wave dashes, and the decorative brackets menus sprinkle around.
_STRIP = re.compile(r"[\s　・･〜～ー－—–\-‐~,、。.!！?？\"'「」『』（）()\[\]【】〈〉《》]")


def normalize_ja(s: str | None) -> str:
    """Fold a Japanese menu string to a comparable key.

    NFKC collapses full-width/half-width and the ﾞ/ﾟ combining forms. We then
    drop punctuation and decoration, so 「牛すじ煮込み」 and 牛すじ煮込 compare
    equal. Kana are deliberately NOT folded to a single form: き and キ are
    different readings on a menu and conflating them would hide real errors.
    """
    if not s:
        return ""
    s = unicodedata.normalize("NFKC", s)
    s = _STRIP.sub("", s)
    return s.casefold()


def similarity(a: str, b: str) -> float:
    """Ratio in [0,1] between two normalized strings."""
    from difflib import SequenceMatcher

    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b).ratio()


def flatten_items(sections: list[dict]) -> list[dict]:
    """Flatten sections into a list of items, each carrying its header."""
    out = []
    for sec in sections or []:
        header = sec.get("header_ja")
        for item in sec.get("items") or []:
            out.append({**item, "_header": header})
    return out


def load_labels(only: list[str] | None = None) -> list[dict]:
    """Load every label file, optionally filtered to a list of image stems."""
    labels = []
    for path in sorted(LABELS_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        data["_path"] = str(path)
        if only and Path(data["image"]).stem not in only:
            continue
        labels.append(data)
    return labels


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
