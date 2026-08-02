# お品書き / Oshinagaki

Japanese menu scanner and learning tool for iOS. Point your camera at an izakaya menu, get a structured list of dishes with translation, furigana, romaji, a plain-English description of what the dish actually is, plus ordering support and vocabulary saving.

**Status:** pre-development. PRD drafted, nothing built yet.

## Docs

- [`docs/PRD.md`](docs/PRD.md) — full product requirements (v1 draft, Aug 2026)

## Planned stack

- iOS 17+, SwiftUI, AVFoundation, Vision, SwiftData
- SQLite/GRDB bundled food dictionary (~5,000 terms)
- Thin backend (Cloudflare Workers) proxying a VLM, with dish-level caching

## Next step

Phase 0 validation: collect a labelled test set of 50–100 real izakaya menu photos and benchmark 2–3 VLMs on parse accuracy and cost before writing any parsing code.
