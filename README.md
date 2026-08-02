# japan-menu-app

Working app title: お品書き / *Oshinagaki* (placeholder, see open question #4 in the PRD).

Japanese menu scanner and learning tool for iOS. Point your camera at an izakaya menu, get a structured list of dishes with translation, furigana, romaji, a plain-English description of what the dish actually is, plus ordering support and vocabulary saving.

**Status:** Phase 0 (validation). No app code yet — the benchmark harness is in place and the test set is being collected.

## Docs

- [`docs/PRD.md`](docs/PRD.md) — full product requirements (v1 draft, Aug 2026)
- [`benchmark/README.md`](benchmark/README.md) — parse-accuracy harness: how to label images and benchmark models

## Planned stack

- iOS 17+, SwiftUI, AVFoundation, Vision, SwiftData
- SQLite/GRDB bundled food dictionary (~5,000 terms)
- Thin backend (Cloudflare Workers) proxying a VLM, with dish-level caching

## Phase 0

Build a labelled test set of 50–100 real izakaya menu photos, then benchmark 2–3 vision models on parse accuracy and cost. Go/no-go before any parsing code gets written.

The current set is 47 web-sourced menu images: a legitimate clean baseline, but not a substitute for photos taken in a real venue. Chalkboards, 短冊 wall strips, dim light, glare, and angled shots are still missing, and those are exactly where the product has to work. Field photos are labelled with `provenance: field` and reported separately.

Menu images are gitignored — they are other people's copyrighted menus. The labels in `benchmark/labels/` are the artifact worth keeping.
