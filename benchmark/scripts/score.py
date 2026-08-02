#!/usr/bin/env python3
"""Grade a parse run against the hand-written ground-truth labels.

    python3 benchmark/scripts/score.py benchmark/results/<run>.json
    python3 benchmark/scripts/score.py <run>.json --by script --per-image

Metrics, and why each one exists:

  item recall      Did we find the dishes? The headline number — the PRD's
                   >=90% extraction target is this.
  item precision   Did we invent dishes that are not on the menu? A hallucinated
                   item is worse than a missed one, because the user orders it.
  price accuracy   Of the items we matched, did the right price attach? This is
                   the metric multi-column layouts break, and it is invisible if
                   you only measure recall.
  header handling  Section headers must not be emitted as dishes.
  decorative leak  Slogans, shop names and tax notices emitted as orderable
                   items. Counted separately because it is a distinct bug with a
                   distinct fix (prompt, not model).
  confidence       Is `low` confidence actually less accurate than `high`? If
                   not, the confidence signal is noise and cannot be shown in
                   the UI.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import RESULTS_DIR, ROOT, flatten_items, load_labels, normalize_ja, similarity, write_json  # noqa: E402


def match_items(gt: list[dict], pred: list[dict], threshold: float) -> tuple[list[tuple[int, int, float]], set[int], set[int]]:
    """Greedy best-first matching between ground-truth and predicted items.

    Highest-similarity pairs are consumed first, so a menu listing 唐揚げ twice
    matches both occurrences rather than collapsing them. Returns the matched
    pairs plus the unmatched indices on each side.
    """
    gt_keys = [normalize_ja(i.get("name_ja")) for i in gt]
    pred_keys = [normalize_ja(i.get("name_ja")) for i in pred]

    candidates = []
    for gi, gk in enumerate(gt_keys):
        for pi, pk in enumerate(pred_keys):
            score = 1.0 if (gk and gk == pk) else similarity(gk, pk)
            if score >= threshold:
                candidates.append((score, gi, pi))
    candidates.sort(reverse=True)

    matches, used_gt, used_pred = [], set(), set()
    for score, gi, pi in candidates:
        if gi in used_gt or pi in used_pred:
            continue
        used_gt.add(gi)
        used_pred.add(pi)
        matches.append((gi, pi, score))

    return matches, set(range(len(gt))) - used_gt, set(range(len(pred))) - used_pred


def score_image(label: dict, result: dict, threshold: float) -> dict:
    gt_items = flatten_items(label.get("sections", []))
    pred_items = flatten_items(result.get("parsed", {}).get("sections", []))

    matches, missed, spurious = match_items(gt_items, pred_items, threshold)

    # Price binding: only meaningful where ground truth actually has a price.
    price_total = price_right = price_null = 0
    for gi, pi, _ in matches:
        if gt_items[gi].get("price") is None:
            continue
        price_total += 1
        p = pred_items[pi].get("price")
        if p == gt_items[gi]["price"]:
            price_right += 1
        elif p is None:
            price_null += 1

    # Headers
    gt_headers = {normalize_ja(s.get("header_ja")) for s in label.get("sections", []) if s.get("header_ja")}
    pred_headers = {
        normalize_ja(s.get("header_ja"))
        for s in result.get("parsed", {}).get("sections", [])
        if s.get("header_ja")
    }

    # Two distinct pollution failures among the spurious items:
    # a header emitted as a dish, and decorative text emitted as a dish.
    decor_keys = {normalize_ja(t) for t in label.get("decorative_text", []) if t}
    header_as_item = decor_as_item = 0
    for pi in spurious:
        key = normalize_ja(pred_items[pi].get("name_ja"))
        if key in gt_headers:
            header_as_item += 1
        elif any(key and (key in d or d in key) for d in decor_keys if d):
            decor_as_item += 1

    # Near misses: an unmatched ground-truth item whose closest prediction is
    # recognisably the same dish with a misread character (牡蠣土鍋ご飯 for
    # 牡蠣土鍋ごはん). Without this, one misread name is counted twice — once as
    # a miss and once as a hallucination — so precision looks worse than it is.
    # These are a dictionary/reading problem, not a detection problem.
    near_misses = []
    for gi in sorted(missed):
        gk = normalize_ja(gt_items[gi].get("name_ja"))
        best, best_pi = 0.0, None
        for pi in spurious:
            s = similarity(gk, normalize_ja(pred_items[pi].get("name_ja")))
            if s > best:
                best, best_pi = s, pi
        if best_pi is not None and 0.5 <= best < threshold:
            near_misses.append(
                {
                    "expected": gt_items[gi].get("name_ja"),
                    "got": pred_items[best_pi].get("name_ja"),
                    "similarity": round(best, 3),
                }
            )

    # Confidence calibration
    conf = defaultdict(lambda: {"matched": 0, "total": 0})
    for pi, item in enumerate(pred_items):
        bucket = item.get("confidence") or "unknown"
        conf[bucket]["total"] += 1
        if pi not in spurious:
            conf[bucket]["matched"] += 1

    return {
        "image": label["image"],
        "attributes": label.get("attributes", {}),
        "gt_items": len(gt_items),
        "pred_items": len(pred_items),
        "matched": len(matches),
        "missed": len(missed),
        "spurious": len(spurious),
        "exact_name_matches": sum(1 for _, _, s in matches if s == 1.0),
        "price_total": price_total,
        "price_correct": price_right,
        "price_null": price_null,
        "gt_headers": len(gt_headers),
        "pred_headers": len(pred_headers),
        "headers_matched": len(gt_headers & pred_headers),
        "header_as_item": header_as_item,
        "decor_as_item": decor_as_item,
        "near_misses": near_misses,
        "confidence": {k: dict(v) for k, v in conf.items()},
        "missed_names": [gt_items[i].get("name_ja") for i in sorted(missed)],
        "spurious_names": [pred_items[i].get("name_ja") for i in sorted(spurious)],
        "latency_s": result.get("latency_s"),
        "cost_usd": result.get("cost_usd"),
    }


def aggregate(rows: list[dict]) -> dict:
    def total(key: str) -> int:
        return sum(r[key] for r in rows)

    gt, pred, matched = total("gt_items"), total("pred_items"), total("matched")
    price_total, price_right = total("price_total"), total("price_correct")
    gt_h, pred_h, matched_h = total("gt_headers"), total("pred_headers"), total("headers_matched")
    near = sum(len(r["near_misses"]) for r in rows)

    recall = matched / gt if gt else None
    precision = matched / pred if pred else None
    f1 = (2 * recall * precision / (recall + precision)) if recall and precision else None

    latencies = sorted(r["latency_s"] for r in rows if r.get("latency_s") is not None)
    costs = [r["cost_usd"] for r in rows if r.get("cost_usd") is not None]

    return {
        "images": len(rows),
        "gt_items": gt,
        "pred_items": pred,
        "item_recall": recall,
        "item_precision": precision,
        "item_f1": f1,
        "near_misses": near,
        "item_recall_incl_near": ((matched + near) / gt) if gt else None,
        "exact_name_rate": (total("exact_name_matches") / matched) if matched else None,
        "price_accuracy": (price_right / price_total) if price_total else None,
        "price_dropped": (total("price_null") / price_total) if price_total else None,
        "header_recall": (matched_h / gt_h) if gt_h else None,
        "header_precision": (matched_h / pred_h) if pred_h else None,
        "header_as_item": total("header_as_item"),
        "decor_as_item": total("decor_as_item"),
        "latency_p50_s": latencies[len(latencies) // 2] if latencies else None,
        "latency_p95_s": latencies[min(len(latencies) - 1, int(len(latencies) * 0.95))] if latencies else None,
        "mean_cost_usd": (sum(costs) / len(costs)) if costs else None,
    }


def fmt(v, pct: bool = False) -> str:
    if v is None:
        return "  n/a"
    return f"{v * 100:5.1f}%" if pct else f"{v:5.2f}"


def print_block(title: str, agg: dict) -> None:
    n = agg["images"]
    print(f"\n{title}  ({n} image{'' if n == 1 else 's'}, {agg['gt_items']} ground-truth items)")
    print(f"  item recall      {fmt(agg['item_recall'], True)}   <- PRD target >= 90%")
    print(f"  item precision   {fmt(agg['item_precision'], True)}   (hallucinated items)")
    print(f"  item F1          {fmt(agg['item_f1'], True)}")
    if agg["near_misses"]:
        print(
            f"  near misses      {agg['near_misses']:>5}   (item found, name misread — "
            f"recall {fmt(agg['item_recall_incl_near'], True).strip()} if counted as found)"
        )
    print(f"  exact name       {fmt(agg['exact_name_rate'], True)}   (of matched; rest were fuzzy)")
    print(f"  price accuracy   {fmt(agg['price_accuracy'], True)}   (of matched items with a price)")
    print(f"  price dropped    {fmt(agg['price_dropped'], True)}   (price existed, model returned null)")
    print(f"  header recall    {fmt(agg['header_recall'], True)}")
    print(f"  headers as items {agg['header_as_item']:>5}   decorative as items {agg['decor_as_item']}")
    if agg["latency_p50_s"] is not None:
        print(f"  latency p50 {agg['latency_p50_s']}s / p95 {agg['latency_p95_s']}s   <- PRD target p50 < 3s, p95 < 6s")
    if agg["mean_cost_usd"] is not None:
        print(f"  mean cost   ${agg['mean_cost_usd']:.5f}/image")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", type=Path, help="Result file from run_parse.py")
    ap.add_argument("--threshold", type=float, default=0.85, help="Name similarity to count as a match (default: 0.85)")
    ap.add_argument("--by", nargs="*", default=["provenance"], help="Attributes to break results down by (default: provenance)")
    ap.add_argument("--per-image", action="store_true", help="Also print a line per image, worst recall first")
    args = ap.parse_args()

    run_path = args.run if args.run.exists() else RESULTS_DIR / args.run.name
    if not run_path.exists():
        print(f"error: no run file at {args.run}", file=sys.stderr)
        return 1

    run = json.loads(run_path.read_text(encoding="utf-8"))
    by_image = {r["image"]: r for r in run["results"]}

    rows, unlabeled, errored = [], [], []
    for label in load_labels():
        if not label.get("labeled"):
            unlabeled.append(label["image"])
            continue
        result = by_image.get(label["image"])
        if result is None:
            continue
        if "parsed" not in result:
            errored.append((label["image"], result.get("error", "unknown")))
            continue
        rows.append(score_image(label, result, args.threshold))

    print(f"run: {run_path.name}")
    print(f"model: {run['model']} / effort {run['effort']} / prompt {run['prompt']}")

    if not rows:
        print("\nNothing to score yet.")
        if unlabeled:
            print(f"{len(unlabeled)} image(s) still have \"labeled\": false — fill in the ground truth first.")
        if errored:
            print(f"{len(errored)} image(s) failed to parse.")
        return 1

    overall = aggregate(rows)
    print_block("OVERALL", overall)

    # Coverage caveats are printed, never silently dropped.
    if unlabeled:
        print(f"\n  ! {len(unlabeled)} image(s) excluded — not yet labeled")
    if errored:
        print(f"  ! {len(errored)} image(s) excluded — parse failed:")
        for name, err in errored[:5]:
            print(f"      {name}: {err}")

    for attr in args.by:
        groups = defaultdict(list)
        for r in rows:
            groups[r["attributes"].get(attr) or "unset"].append(r)
        if len(groups) < 2 and "unset" in groups:
            continue
        print(f"\n--- by {attr} ---")
        for value, group in sorted(groups.items(), key=lambda kv: str(kv[0])):
            print_block(f"{attr}={value}", aggregate(group))
        if attr == "provenance" and "field" not in groups:
            print(
                "\n  ! No field photos in this set. Web-sourced menus are clean, lit and\n"
                "    straight-on; these numbers do not predict performance in a dim izakaya."
            )

    conf_totals = defaultdict(lambda: {"matched": 0, "total": 0})
    for r in rows:
        for bucket, counts in r["confidence"].items():
            conf_totals[bucket]["matched"] += counts["matched"]
            conf_totals[bucket]["total"] += counts["total"]
    if conf_totals:
        print("\n--- confidence calibration ---")
        for bucket in ("high", "medium", "low", "unknown"):
            c = conf_totals.get(bucket)
            if not c or not c["total"]:
                continue
            print(f"  {bucket:<8} {c['matched'] / c['total'] * 100:5.1f}% correct  (n={c['total']})")
        print("  (if low is not meaningfully worse than high, the signal is noise —\n"
              "   do not surface it in the UI)")

    if args.per_image:
        print("\n--- per image (worst recall first) ---")
        for r in sorted(rows, key=lambda x: (x["matched"] / x["gt_items"]) if x["gt_items"] else 1.0):
            rec = (r["matched"] / r["gt_items"]) if r["gt_items"] else None
            print(f"  {fmt(rec, True)}  {r['image']:<40} {r['matched']}/{r['gt_items']} items, {r['spurious']} spurious")
            if r["missed_names"]:
                print(f"           missed:     {'  '.join(str(n) for n in r['missed_names'][:8])}")
            for nm in r["near_misses"][:5]:
                print(f"           near miss:  {nm['expected']} -> {nm['got']}  ({nm['similarity']})")

    out = RESULTS_DIR / f"{run_path.stem}.score.json"
    write_json(
        out,
        {
            "run": run_path.name,
            "model": run["model"],
            "effort": run["effort"],
            "prompt": run["prompt"],
            "threshold": args.threshold,
            "overall": overall,
            "excluded_unlabeled": unlabeled,
            "excluded_errors": [{"image": n, "error": e} for n, e in errored],
            "per_image": rows,
        },
    )
    print(f"\n-> {out.relative_to(ROOT.parent)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
