#!/usr/bin/env python3
"""Run a vision model over the benchmark images and record structured parses.

Writes one result file per run to benchmark/results/, which score.py then
grades against the hand-written labels. Each run records the model, effort,
prompt, per-image latency, token usage and cost, so two runs are comparable.

    python3 benchmark/scripts/run_parse.py --model claude-opus-5
    python3 benchmark/scripts/run_parse.py --model claude-sonnet-5 --effort medium
    python3 benchmark/scripts/run_parse.py --only dsc-9049 --tag spotcheck
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import IMAGES_DIR, PROMPTS_DIR, RESULTS_DIR, cost_usd, write_json  # noqa: E402

NULLABLE_STR = {"anyOf": [{"type": "string"}, {"type": "null"}]}
NULLABLE_INT = {"anyOf": [{"type": "integer"}, {"type": "null"}]}

MENU_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["sections", "decorative_text"],
    "properties": {
        "sections": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["header_ja", "items"],
                "properties": {
                    "header_ja": NULLABLE_STR,
                    "items": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["name_ja", "note_ja", "price", "price_note", "confidence"],
                            "properties": {
                                "name_ja": {"type": "string"},
                                "note_ja": NULLABLE_STR,
                                "price": NULLABLE_INT,
                                "price_note": NULLABLE_STR,
                                "confidence": {"enum": ["high", "medium", "low"]},
                            },
                        },
                    },
                },
            },
        },
        "decorative_text": {"type": "array", "items": {"type": "string"}},
    },
}


def parse_one(client, model: str, effort: str, prompt: str, max_tokens: int, path: Path) -> dict:
    media = "image/jpeg" if path.suffix.lower() in (".jpg", ".jpeg") else "image/png"
    data = base64.standard_b64encode(path.read_bytes()).decode("utf-8")

    started = time.perf_counter()
    try:
        response = client.messages.create(
            model=model,
            max_tokens=max_tokens,
            output_config={
                "effort": effort,
                "format": {"type": "json_schema", "schema": MENU_SCHEMA},
            },
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "source": {"type": "base64", "media_type": media, "data": data}},
                        {"type": "text", "text": prompt},
                    ],
                }
            ],
        )
    except Exception as exc:  # noqa: BLE001 - one bad image must not kill the run
        return {
            "image": path.name,
            "error": f"{type(exc).__name__}: {exc}",
            "latency_s": round(time.perf_counter() - started, 2),
        }

    latency = round(time.perf_counter() - started, 2)
    usage = response.usage.model_dump() if hasattr(response.usage, "model_dump") else dict(response.usage)

    result = {
        "image": path.name,
        "latency_s": latency,
        "stop_reason": response.stop_reason,
        "usage": usage,
        "cost_usd": cost_usd(model, usage),
    }

    # Safety classifiers can decline with a normal 200 and an empty content
    # array, so check stop_reason before indexing into content.
    if response.stop_reason == "refusal":
        details = getattr(response, "stop_details", None)
        result["error"] = f"refusal ({getattr(details, 'category', None)})"
        return result
    if response.stop_reason == "max_tokens":
        result["error"] = "truncated at max_tokens — raise --max-tokens"
        return result

    text = next((b.text for b in response.content if b.type == "text"), None)
    if text is None:
        result["error"] = "no text block in response"
        return result
    try:
        result["parsed"] = json.loads(text)
    except json.JSONDecodeError as exc:
        result["error"] = f"invalid JSON: {exc}"
        result["raw"] = text
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="claude-opus-5")
    ap.add_argument(
        "--effort",
        default="low",
        choices=["low", "medium", "high", "xhigh", "max"],
        help="Reading a menu is perception, not reasoning — start low and only "
        "raise it if the scorer shows it buys accuracy (default: low)",
    )
    ap.add_argument("--prompt", default="parse_v1.md", help="Filename in benchmark/prompts/")
    ap.add_argument("--max-tokens", type=int, default=8000)
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--only", nargs="*", help="Image stems to run, instead of the whole set")
    ap.add_argument("--tag", default="", help="Label for this run, appended to the result filename")
    args = ap.parse_args()

    try:
        import anthropic
    except ImportError:
        print("error: pip install -r benchmark/requirements.txt", file=sys.stderr)
        return 1

    prompt_path = PROMPTS_DIR / args.prompt
    if not prompt_path.exists():
        print(f"error: no prompt at {prompt_path}", file=sys.stderr)
        return 1
    prompt = prompt_path.read_text(encoding="utf-8")

    images = sorted(p for p in IMAGES_DIR.glob("*.jpg"))
    if args.only:
        wanted = set(args.only)
        images = [p for p in images if p.stem in wanted]
    if not images:
        print("error: no images. Run normalize.py first.", file=sys.stderr)
        return 1

    client = anthropic.Anthropic()
    print(f"{args.model} / effort={args.effort} / {len(images)} image(s)")

    results = []
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = [
            pool.submit(parse_one, client, args.model, args.effort, prompt, args.max_tokens, p)
            for p in images
        ]
        for i, future in enumerate(futures, 1):
            r = future.result()
            results.append(r)
            n = len(r.get("parsed", {}).get("sections", [])) if "parsed" in r else 0
            items = sum(len(s.get("items", [])) for s in r.get("parsed", {}).get("sections", []))
            status = r.get("error") or f"{items} items / {n} sections"
            print(f"  [{i}/{len(images)}] {r['image']}: {status} ({r['latency_s']}s)")

    ok = [r for r in results if "parsed" in r]
    latencies = sorted(r["latency_s"] for r in ok)
    total_cost = sum(r["cost_usd"] or 0 for r in ok)

    def pct(p: float) -> float | None:
        if not latencies:
            return None
        return latencies[min(len(latencies) - 1, int(len(latencies) * p))]

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    name = f"{run_id}_{args.model}_{args.effort}" + (f"_{args.tag}" if args.tag else "")
    out = RESULTS_DIR / f"{name}.json"
    write_json(
        out,
        {
            "run_id": run_id,
            "model": args.model,
            "effort": args.effort,
            "prompt": args.prompt,
            "max_tokens": args.max_tokens,
            "image_count": len(images),
            "success_count": len(ok),
            "latency_p50_s": pct(0.5),
            "latency_p95_s": pct(0.95),
            "total_cost_usd": round(total_cost, 4),
            "mean_cost_per_image_usd": round(total_cost / len(ok), 5) if ok else None,
            "results": results,
        },
    )

    print(f"\n{len(ok)}/{len(images)} parsed")
    print(f"latency p50 {pct(0.5)}s / p95 {pct(0.95)}s")
    print(f"cost ${total_cost:.4f} total, ${total_cost / len(ok):.5f}/image" if ok else "")
    print(f"-> {out}")
    print("\nNote: this is one API call per image with no cached prefix. In production "
          "the dish-level cache absorbs enrichment; only this parse call recurs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
