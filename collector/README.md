# Collector — hosted photo collection + labeling

Always-on web app for building the benchmark set. Friends open one URL from
their phone, enter the shared passcode and their name, and can:

- **Upload menu photos** taken in real venues (the missing `provenance: field`
  data). Photos are downscaled in the browser to the benchmark's normalized
  1568px before upload; the full-resolution original is stored too.
- **Label images** — the same editor as `benchmark/labeling/`, with claim
  locking, touch pan/pinch-zoom, and a review flow. Uploading needs no
  Japanese; labeling does.

Contributor labels stay `verified: false` until you check them against the
image and mark them verified. Any content edit resets verification.

The repo remains the source of record: `benchmark/scripts/sync_remote.py`
moves data both ways, and `git diff benchmark/labels` is the review gate.

## First-time deploy

```bash
cd collector
npm install
npx wrangler login                          # opens browser, one time
npx wrangler r2 bucket create japan-menu-collector
npx wrangler secret put PASSCODE            # the passcode you'll share
npx wrangler deploy                         # prints the workers.dev URL
```

Then seed the remote with the existing set and check it loads:

```bash
export COLLECTOR_URL=https://japan-menu-collector.<your-subdomain>.workers.dev
export COLLECTOR_PASSCODE=<the passcode>
.venv/bin/python benchmark/scripts/sync_remote.py push
```

Share the URL + passcode privately. The images are third-party photos and
the passcode is the only gate, so treat the pair like a key.

## The loop

```bash
# after friends upload / label:
.venv/bin/python benchmark/scripts/sync_remote.py pull
git diff benchmark/labels        # review contributor labels
git add benchmark/labels && git commit

# after you label or verify locally, or add web images:
.venv/bin/python benchmark/scripts/sync_remote.py push
```

Pull brings normalized images into `benchmark/images/` (ready for
`run_parse.py`), full-resolution originals into `menu-pics/field/`, and labels
into `benchmark/labels/`. Pull overwrites local labels — git is the safety
net. Push refuses to overwrite a remote label that differs (someone may have
labeled it since your last pull); pull first, or `--force-labels`.

## Local development

```bash
cd collector
npm run dev        # http://localhost:8787, passcode "dev" (.dev.vars)
```

`wrangler dev` simulates R2 locally (state in `.wrangler/`, gitignored).
Seed it with `sync_remote.py push --url http://localhost:8787 --passcode dev`.

## Storage layout (R2 bucket)

```
images/<stem>.jpg        normalized JPEG, 1568px long edge
originals/<stem>.<ext>   full-res original of a field upload
labels/<stem>.json       ground truth, same schema as benchmark/labels/
meta/<stem>.json         who uploaded, when, venue note, original ext
claims/<stem>            soft lock while someone labels (30 min TTL)
```

Field uploads are named `field-<utc timestamp>-<rand>`. Deleting a photo in
the UI (blurry shots, duplicates) only works while it is unlabeled.

## Costs

Cloudflare free tier covers this comfortably: R2 gives 10GB storage and
millions of reads/writes per month; a few hundred menu photos at ~500KB
normalized + a few MB original is single-digit GB. Workers free tier is
100k requests/day.
