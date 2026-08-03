# Parse benchmark

Phase 0 of the PRD: build a labelled test set, then benchmark vision models on it before writing any parsing code. This directory is the harness.

```
benchmark/
├── images/      normalized JPEGs        (gitignored — third-party photos)
├── labels/      ground truth, one JSON per image   ← the tracked artifact
├── prompts/     parse prompts, versioned
├── results/     run + score output      (gitignored)
├── schema/      JSON Schema for a label file
└── scripts/     normalize / init_labels / run_parse / score
```

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r benchmark/requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
```

## Workflow

```bash
# 1. Normalize source photos to a fixed format and resolution
.venv/bin/python benchmark/scripts/normalize.py menu-pics

# 2. Create a label stub per image
.venv/bin/python benchmark/scripts/init_labels.py --provenance web

# 3. Label by hand — see below

# 4. Run a model
.venv/bin/python benchmark/scripts/run_parse.py --model claude-opus-5

# 5. Grade it
.venv/bin/python benchmark/scripts/score.py benchmark/results/<run>.json --per-image
```

Steps 4 and 5 are cheap to repeat. Step 3 is the work.

## Labeling

The fastest way to label is the web tool — image and form side by side, schema enforced by the UI, saves straight into `benchmark/labels/`:

```bash
python3 benchmark/labeling/server.py        # -> http://localhost:8788
```

To let other people label (they need to read Japanese), expose it with a tunnel and share the URL privately:

```bash
cloudflared tunnel --url http://localhost:8788    # or: tailscale funnel 8788
```

Contributor labels record who wrote them (`labeled_by`) and stay `verified: false` until you check them against the image and mark them verified in the tool. The scorer warns when unverified labels are included in a run, and any content edit resets verification. Ground-truth errors poison every downstream metric silently, so review everything you didn't write yourself, and spot-check what you did.

When a session ends, the labels are ordinary files: `git diff benchmark/labels`, commit. Take the tunnel down afterwards — the images are third-party photos and anyone with the URL can write labels.

### Conventions

`benchmark/labels/menu.json` is a filled-in worked example (transcribed but unverified, so check it before trusting numbers that include it). Copy its conventions:

- `name_ja` is the dish name **exactly as printed**. No normalizing, no added kanji.
- Parenthetical detail goes in `note_ja`, never in the name. `バター醤油 or カレー or のりしお` is a note on 情熱のフライドポテト, not part of it.
- Quantity and pricing qualifiers (`2人前`, `各1本`, `時価`) go in `price_note`.
- Section headers go in `header_ja`. Items under no header go in a section with `header_ja: null`.
- **Fill in `decorative_text`.** Shop names, slogans, tax notices, mascot dialogue. This is what lets the scorer distinguish "invented a dish" from "emitted the tax notice as a dish" — different bugs, different fixes.
- Set `"labeled": true` when done. The scorer skips anything still `false` and tells you how many it skipped.

Attributes drive the breakdown tables, so fill them in even before you transcribe items. `provenance` is the important one.

### provenance: `web` vs `field`

Web-sourced menu images are straight-on, evenly lit, in focus, and high resolution. Real input is a phone photo in a dark basement, held at an angle, slightly blurred, one-handed. **A benchmark of web images will report accuracy the app never achieves in production.** The scorer reports the two groups separately and warns when the set contains no field photos. Keep the web images as a clean baseline; treat the field numbers as the real ones.

## What the scorer measures

| Metric | What it catches |
|---|---|
| item recall | Missed dishes. The PRD's ≥90% target. |
| item precision | Invented dishes. Worse than a miss — the user orders it. |
| near misses | Item found but a character misread. Reported separately so one misread name isn't counted as both a miss and a hallucination. Signals a dictionary problem, not a detection problem. |
| price accuracy | Wrong price bound to a right item. Invisible if you only track recall, and the thing multi-column layouts break. |
| price dropped | Price was printed, model returned null. |
| header recall / headers-as-items | Section headers must be structure, not dishes. |
| decorative-as-items | Slogans and tax notices emitted as orderable items. |
| confidence calibration | Whether `low` confidence is actually less accurate than `high`. If it isn't, the signal is noise and must not reach the UI — the PRD's "wrong is worse than absent" principle depends on it being real. |
| latency p50/p95, cost/image | The PRD's 3s target and the unit economics. |

Name matching is fuzzy above `--threshold` (default 0.85). CJK strings are short, so this is strict: ごはん vs ご飯 scores 0.77 and lands in the near-miss bucket rather than counting as a match. That is deliberate — a learner shown the wrong okurigana has been given wrong information.

## Sweeping

Resolution and effort both trade cost against accuracy. Vary one at a time:

```bash
# Resolution: 1568px standard tier vs 2576px high-res (up to ~3x image tokens)
.venv/bin/python benchmark/scripts/normalize.py menu-pics --max-dim 2576 --suffix hi

# Effort: reading a menu is perception, not reasoning — start low
.venv/bin/python benchmark/scripts/run_parse.py --model claude-opus-5 --effort low
.venv/bin/python benchmark/scripts/run_parse.py --model claude-opus-5 --effort medium

# Models
.venv/bin/python benchmark/scripts/run_parse.py --model claude-sonnet-5
.venv/bin/python benchmark/scripts/run_parse.py --model claude-haiku-4-5
```

Every run writes its model, effort, prompt, latency, tokens and cost into the result file, so two runs are directly comparable. Prompts are versioned in `prompts/` — copy `parse_v1.md` to `parse_v2.md` rather than editing in place, or you lose the ability to compare.

## Cost note

Each run is one uncached API call per image. That is the right number for the per-scan cost the PRD asks you to validate, but it is not the whole production picture: dish-level caching absorbs the enrichment calls, so only this parse call recurs per scan. Model the worst case (a resident scanning daily) against ¥600/month using the per-image number this prints.
