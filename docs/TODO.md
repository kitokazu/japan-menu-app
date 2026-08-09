# Your TODO list

Ordered by what unblocks what. Items marked 🔑 are things only you can do; nothing downstream of them can be faked.

## Now (this week)

1. 🔑 **Download an iOS simulator runtime.** Xcode > Settings > Components > iOS 26.5. The app compiles but can't run until a simulator exists. Then: open `app/Oshinagaki.xcodeproj`, pick a simulator, Run. Use the photo-library button (the simulator has no camera) and any menu photo; you'll get the fixture result list.
2. 🔑 **Set your Anthropic API key and smoke-test the benchmark runner.** It's the one script not yet exercised end to end:
   ```bash
   export ANTHROPIC_API_KEY=sk-ant-...
   .venv/bin/python benchmark/scripts/run_parse.py --only menu --tag spotcheck
   .venv/bin/python benchmark/scripts/score.py benchmark/results/<the run file>.json
   ```
   Costs a few cents. If it works on one image, the full 47 is one command.
3. 🔑 **Verify `benchmark/labels/menu.json`.** I transcribed it from the image but did not independently verify it. Open the image next to the label and check every item and price. It's your worked example; if it's wrong, everything you label after it copies the mistake.
4. 🔑 **Deploy the hosted collector and share it.** The app is built and tested locally (`collector/`); it needs your Cloudflare account:
   ```bash
   cd collector && npm install
   npx wrangler login
   npx wrangler r2 bucket create japan-menu-collector
   npx wrangler secret put PASSCODE
   npx wrangler deploy
   export COLLECTOR_URL=<printed workers.dev URL> COLLECTOR_PASSCODE=<passcode>
   .venv/bin/python benchmark/scripts/sync_remote.py push   # seed with the 47 web images
   ```
   Then send the URL + passcode to friends in Japan. Anyone can upload menu photos from their phone at dinner; Japanese readers can label. See `collector/README.md`.
5. **Decide the app name direction** (open question #4). It blocks the bundle ID, App Store name reservation and ASO later. *Current call (Aug 2026): the project is "japan-menu-app" for now; Oshinagaki stays a UI placeholder. Revisit before TestFlight.*

## Ongoing (the 2–3 week background loop)

6. 🔑 **Photograph menus in real venues — and upload on the spot.** Target 30–50, weighted toward what the current set completely lacks: chalkboard specials, 短冊 wall strips, brush script, dim light, glare, angled one-handed shots. Every dinner out is a data-collection run, and with the collector deployed, upload happens at the table: open the URL, snap, done. Friends with the passcode can do the same from their own dinners. Shoot the ugly ones on purpose; a photo you're embarrassed by is a good test case.
7. 🔑 **Label as you go, review what others label.** Labeling happens in the same hosted app (or the local tool, `python3 benchmark/labeling/server.py`, for offline sessions). Contributor labels arrive marked `needs review`; verify them against the image before they count. After each session:
   ```bash
   .venv/bin/python benchmark/scripts/sync_remote.py pull
   git diff benchmark/labels    # review, then commit
   ```
   Do 2–3 per evening rather than a heroic weekend; label quality drops fast with fatigue.
8. **Label 10–15 of the existing web images too.** They're the clean baseline the field numbers get compared against, and labeling easy images first builds the habit before the chalkboards test it.

## When ~10 field photos are labeled

9. **Run the first real benchmark sweep:**
   ```bash
   .venv/bin/python benchmark/scripts/run_parse.py --model claude-opus-5 --effort low
   .venv/bin/python benchmark/scripts/run_parse.py --model claude-sonnet-5 --effort low
   .venv/bin/python benchmark/scripts/run_parse.py --model claude-haiku-4-5 --effort low
   .venv/bin/python benchmark/scripts/score.py benchmark/results/<run>.json --per-image
   ```
   Look at: field recall vs web recall, price accuracy on multi-column menus, whether `low` confidence is actually less accurate than `high`, and cost per image.
10. **Make the go/no-go call** (PRD Phase 0): does parse quality on hard handwritten menus hold, or does V1 need a "we couldn't read this" path? Does worst-case cost (resident scanning daily) clear ¥600/month?

## After go/no-go (unblocked by the numbers)

11. Build the Cloudflare Worker with the winning model, and swap `FixtureParseService` for a `BackendParseService` — the `ParseService` protocol in `app/Oshinagaki/Services/ParseService.swift` is the only seam that changes.
12. Price the tiers with real per-scan cost (PRD §9).
13. Start the curated dictionary seed list (the parser's uncached-term log tells you what to add first — but that log only exists once the backend does).

---

## Why the field photos and labels are non-negotiable

**The field photos: because the benchmark currently measures a product you're not building.** All 47 current images came off the web, which means they were taken by restaurant owners and food bloggers in good light, straight-on, in focus, often digitally rendered rather than photographed. Your user is in a dim basement, three drinks in, holding a phone one-handed at an angle over a laminated menu with a glare stripe across it. Those two image distributions are different enough that accuracy on one says almost nothing about the other; OCR-type systems degrade non-linearly with blur, low contrast and perspective. If you benchmark on web images, pick a model, price the product, and ship, the first real izakaya will hand you a failure rate you never measured. The entire premise of the app is "works where Google Lens visibly fails," and the places Lens fails are exactly the conditions missing from the current set. You're also the only person who can fix this: it requires physically being in izakayas with a phone.

**The labels: because accuracy is undefined without ground truth.** Every number the scorer prints (recall, precision, price accuracy) is computed by comparing the model's output against what the menu actually says. No labels, no comparison, no numbers. And the model can't grade itself: using a model's output as the answer key would just measure agreement with its own mistakes. A human has to write down the truth once, per image.

The labels then pay for themselves three more times:

- **Every tuning decision becomes measurable.** Model A vs model B, effort low vs medium, 1568px vs 2576px, prompt v1 vs v2 — each is a 5-minute run against a fixed answer key instead of a vibe check. Without labels you're choosing your core infrastructure by eyeballing outputs.
- **They're a regression suite.** When you change the prompt in month 3 and something quietly breaks on chalkboards, the labeled set catches it. This is the PRD's "you cannot tune what you can't measure."
- **They validate the trust features.** "Wrong is worse than absent" only works if the confidence marker means something. The calibration table in the scorer — is `low` actually less accurate than `high`? — can only be computed against labels. If confidence turns out to be noise, you must not show it, and you can only discover that with ground truth.

The unglamorous version: it's a few evenings of transcribing menus into JSON, and it's the difference between knowing your parse accuracy and guessing it. The PRD calls the dictionary "your actual moat" — the labeled test set is the same species of work, and it comes first.
