# PRD — Japanese Menu Scanner & Learning Tool

**Working title:** お品書き / *Oshinagaki* (the traditional word for a handwritten izakaya menu — placeholder, see Naming)
**Platform:** iOS (SwiftUI, iOS 17+)
**Team:** Solo developer
**Status:** Draft v1
**Date:** August 2026

---

## 1. Summary

An iOS app that turns a photo of a Japanese menu into a structured, readable, learnable list of dishes — with translation, hiragana reading, romaji, a plain-English description of what the dish actually *is*, and the tools to order it out loud and remember it later.

The wedge is **izakaya menus specifically**: brush fonts, vertical text, handwritten daily specials, chalkboards, no photos. These break every existing OCR translation tool, and they're exactly where a foreigner needs the most help.

---

## 2. Problem

Existing tools answer "what does this text say." They don't answer the four questions you actually have while holding a menu:

1. **What does it say?** — Google Lens does this, badly, on brush fonts and vertical layouts.
2. **What *is* it?** — "Shirako" is a correct translation and tells you nothing. It's cod milt. Custard texture. Served raw with ponzu or grilled.
3. **How do I say it?** — You need to order. Translation is half the job; pronunciation is the other half.
4. **How do I remember it?** — Menu kanji (焼, 揚, 蒸, 刺, 煮, 和) are extremely high-frequency in daily life in Japan and nearly absent from textbooks. Every menu is a free vocabulary lesson that currently evaporates.

**Environmental constraints that shape everything:** dim basement izakaya, poor cellular signal, you're a few drinks in, friends are waiting, and there's social pressure to order fast. Speed and one-handed operation dominate every other consideration.

---

## 3. Users

### Persona A — Resident learner ("Sam")
Lives in Japan 1–5 years. N5–N3. Can read some kana, struggles with kanji. Eats out weekly. Actively studying, probably already uses Anki. Wants menus to be a study input, not a wall.

- **Frequency:** 2–8 scans/week, sustained over years
- **Values:** accuracy of readings, retention features, offline capability, feeling less illiterate
- **Willing to pay:** monthly/annual subscription, if it's genuinely part of their study routine

### Persona B — Tourist ("Alex")
In Japan 7–14 days. Zero Japanese. Wants to eat well and avoid ordering something alarming. Will never open the app again after the trip.

- **Frequency:** 1–3 scans/day for two weeks, then zero
- **Values:** speed, zero setup, no account, dietary safety, images
- **Willing to pay:** a one-time trip fee. Will not start a subscription.

### ⚠️ The central product tension

**These are different products.** Serving both equally is the biggest risk in this PRD. Alex wants the answer in three seconds with no depth. Sam wants depth. If you put learning features in front of the answer, you lose Alex. If you strip them out, you lose Sam.

**Resolution: progressive disclosure.** One shared scan engine and one shared result screen. The fast answer is always the top layer. Everything Sam wants — readings, kanji breakdown, save-to-deck — lives one tap *below* the fast answer, never in front of it. Learning is opt-in depth, not a mandatory mode toggle.

This also resolves pricing (§9): trip pass for Alex, subscription for Sam.

---

## 4. Positioning

| | Google Lens / Translate | Yomiwa / Jisho-type | **This app** |
|---|---|---|---|
| Brush & vertical text | Poor | Poor | **Primary use case** |
| Menu structure (item ↔ price) | None | None | **Parsed & structured** |
| Readings (furigana) | No | Yes, generic | **Food-specific dictionary** |
| "What is this dish?" | No | No | **Yes** |
| Ordering support | No | No | **Yes** |
| Learning / SRS | No | Partial | **Yes, with Anki export** |

Google Lens is free, ubiquitous, and good enough for printed signage. Don't compete on breadth. Compete on **depth in one context** — the izakaya menu — where Google visibly fails.

---

## 5. Design principles

1. **Three seconds or it doesn't matter.** p50 from shutter to readable result under 3s. This is the single most important number in the app.
2. **The answer first, the lesson second.** Never gate the translation behind a learning interaction.
3. **Assume a dark basement with no signal.** Dark mode default, high contrast, large targets, one-handed reachability, aggressive offline caching.
4. **Be discreet.** One photo, then look at your phone. Don't make people wave a phone at a menu in front of staff. (Live AR overlay is a V2 nice-to-have, not the primary flow.)
5. **Wrong is worse than absent.** One incorrect furigana destroys a learner's trust permanently. Show confidence, and show nothing rather than a guess.

---

## 6. Feature specification

### V1 — Ship this

**6.1 Capture**
- Camera capture with auto edge/text detection, plus photo library import
- Multi-shot for long or multi-page menus, stitched into one result set
- On-device pre-check (Vision framework) to reject "no text found" before spending an API call
- Torch toggle, prominent — izakayas are dark

**6.2 Parse**
- Image → structured JSON: `{ item_name_ja, price, category, section_header, confidence }`
- Handles vertical text (縦書き), brush fonts, chalkboard, handwriting
- Correctly distinguishes dish names from category headers (本日のおすすめ) and decorative text
- Correctly binds prices to their items

**6.3 Result list**
- Scrollable list, grouped by menu section
- Each row: Japanese (large) / English / price
- Instant. No per-item loading spinners — enrich lazily in the background.

**6.4 Item detail** (tap a row)
- Japanese with furigana above kanji
- Full hiragana reading
- Romaji
- English translation
- **Description: 1–2 sentences on what it actually is** — ingredients, preparation, texture, how it's served
- Kanji breakdown: each character with meaning and common readings
- Save to vocabulary ★

**6.5 Ordering mode**
- Full-screen, maximum-size Japanese text with furigana
- Designed to be read aloud or pointed at
- Optional TTS playback (AVSpeechSynthesizer, ja-JP)
- This is cheap to build and disproportionately valuable. Do not cut it.

**6.6 Vocabulary & history**
- Saved items list
- Scan history with thumbnails (find that place you went last month)
- Local-only, no account required in V1

**6.7 Offline fallback**
- Bundled dictionary (SQLite) covering ~5,000 food/drink terms
- Vision framework on-device OCR when there's no signal
- Degraded but functional: readings and translations yes, rich descriptions no

### V2 — Next

**6.8 Images**
Requested, but the most expensive feature relative to value. Note that a photo of 白子 is a white blob — the *description* often does more work. Staged approach:
- **V1 stopgap:** "See photos →" button deep-linking to Google Images / Tabelog search for the dish name. Zero licensing exposure, zero cost.
- **V2:** curated licensed image library for the top ~1,000 dishes (covers the large majority of izakaya menus). Highest quality, real upfront cost, safest legally.
- **Rejected:** AI-generated images. Plausible-looking but risks quietly misrepresenting unfamiliar dishes, which is precisely the case where the user is relying on you.

**6.9 SRS review**
- Daily review queue over saved items (SM-2 or FSRS)
- **Anki `.apkg` export** — high leverage with the Japanese-learning community, strong word-of-mouth driver
- "This kanji has appeared on 12 menus you've scanned" — connects study to lived experience

**6.10 Allergen & dietary flags**
- Flag likely presence of: pork, alcohol, shellfish, dairy, gluten, egg, **dashi/fish** (near-universal in izakaya food and the #1 vegetarian trap in Japan)
- Must ship with an unmissable disclaimer and a "confirm with staff" phrase card in Japanese
- High value, genuinely underserved, but carries liability — treat carefully

**6.11 Live camera overlay**
Translated text over the live camera feed. Flashy, good for demos and quick scanning, but less useful than a parsed list you can scroll. Build it after the core is solid.

### Later
- iPad, Apple Watch quick-glance, Shortcuts/widget
- Shared menus (crowdsourced corrections per restaurant)
- Sake/shochu specialisation — brands, regions, flavour profiles (獺祭 = だっさい; a genuinely underserved niche)
- Android

---

## 7. Technical architecture

```
iPhone (SwiftUI)
  ├─ AVFoundation capture
  ├─ Vision (VNRecognizeTextRequest, ja-JP)  → pre-check + offline fallback
  ├─ SQLite/GRDB bundled dictionary          → readings, offline
  ├─ SwiftData                               → saved items, history, SRS state
  └─ HTTPS →  Thin backend (Cloudflare Workers or similar)
                ├─ VLM proxy (hides API keys)
                ├─ Dish-level cache  ← the key cost lever
                ├─ Dictionary/description service
                └─ StoreKit receipt validation
```

**Why VLM-first, not OCR-first.** Classical OCR pipelines (Vision, Google Cloud Vision) do character recognition well on printed text but fail on brush fonts and vertical layouts, and give you *no structure* — you get text soup and then have to solve item/price/header segmentation yourself with brittle rules. A vision-language model with a strict output schema does recognition, layout understanding, and segmentation in a single call, and handles stylised fonts far better. Use a cost-efficient model tier; you don't need frontier reasoning to read a menu.

Vision framework remains valuable as: (a) a free pre-check so you don't burn API calls on blurry shots, (b) the offline path.

**Caching is your margin.** Cache at the **dish level, not the image level**. Normalise the extracted Japanese string and cache its enrichment (reading, translation, description, kanji breakdown) permanently. 焼き鳥 gets enriched once, ever, across all users. After a few thousand users the enrichment cost trends toward zero and only the per-image parse call persists. Build this from day one, not as an optimisation later.

**Do not build a microservice architecture.** You're solo. One Worker, one KV/D1 store, one queue if needed.

---

## 8. Data & dictionary strategy

This is the unglamorous work that makes the product trustworthy, and it's your actual moat.

- **Base:** JMdict/EDICT for general vocabulary
- **Problem:** MeCab/Kuromoji with IPADic or UniDic will confidently return *wrong* readings for food vocabulary — 鮟鱇 (あんこう), 湯葉 (ゆば), 拵え, 饂飩, plus sake brand names, which are essentially all irregular
- **Solution:** hand-curated food & drink dictionary, seeded with the ~3,000–5,000 terms covering the overwhelming majority of izakaya menus. Reading, translation, description, category, allergen tags.
- **Growth:** log every uncached term the parser encounters; review the frequency-ranked backlog weekly. The app tells you what to add next.
- **Confidence display:** curated entries show clean. Model-generated entries carry a subtle "auto" marker. Never present a guess as authoritative.

Budget real time for this. It's probably 3–4 weeks of your effort spread across the build, and it's the difference between "another Google Translate wrapper" and something learners recommend to each other.

---

## 9. Business model

| Tier | Price | Gets |
|---|---|---|
| Free | ¥0 | 5 scans/month, basic translation + reading |
| **Trip Pass** | ¥1,200 / 14 days | Unlimited scans, all features, no auto-renew |
| **Subscription** | ¥600/mo or ¥4,800/yr | Unlimited + SRS + Anki export + sync |

The two paid tiers map cleanly onto the two personas. The Trip Pass is important: tourists will pay once but will not start a subscription for a two-week trip, and forcing them to try is how you get one-star reviews and chargebacks. Non-renewing consumable — set expectations clearly.

**Unit economics to validate before launch:** per-scan VLM cost at your chosen model and image resolution, multiplied by heavy-user scan frequency, against ¥600/month. Model the worst case (a resident scanning daily) and confirm you're not upside-down. Dish-level caching is what makes this work.

**Market:** ~3M foreign residents in Japan (the durable subscription base) and ~35M annual inbound tourists (the volume base). You don't need much of either.

---

## 10. Success metrics

**Primary**
- Time-to-result: p50 < 3s, p95 < 6s
- Parse accuracy: ≥90% of menu items correctly extracted on a held-out izakaya menu test set
- Reading accuracy: ≥98% on curated-dictionary terms (trust is fragile here)

**Engagement**
- Scans per active user per week
- Item-detail open rate (are people going one layer deeper?)
- Ordering mode usage (validates the thesis that saying it matters)
- Sam: D30 retention, items saved per user
- Alex: scans per trip, completion of trip pass value

**Business**
- Free → paid conversion by persona
- Cost per scan trending down as cache warms
- Anki export usage (leading indicator of word-of-mouth)

**Build a labelled test set of 50–100 real izakaya menu photos before you write parsing code.** Include the ugly ones: chalkboards, brush script, dim light, angles, glare. You cannot tune what you can't measure, and this set is how you compare model options.

---

## 11. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Google Lens is free and "good enough" for many | High | Compete on depth in one context; lead marketing with brush-font/vertical cases where Lens visibly fails |
| Two-persona split fragments the product | High | Progressive disclosure (§3); revisit at 3 months of data and consider picking one |
| VLM cost exceeds subscription revenue for heavy users | Medium | Dish-level caching from day one; fair-use cap; validate economics pre-launch |
| Wrong readings destroy learner trust | Medium | Curated dictionary; confidence markers; easy in-app correction reporting |
| Allergen data liability | Medium | Prominent disclaimer; ship a "please confirm with staff" phrase card; consider deferring past V2 |
| Solo-dev scope creep | High | V1 list above is already at the edge of a 3–4 month solo build. Cut images and SRS from V1 without guilt. |

---

## 12. Open questions

1. Does the parse quality hold on genuinely hard handwritten chalkboards, or does it degrade enough to need a "we couldn't read this, try again" path? **Test before committing.**
2. Is dish description quality good enough from a model alone, or does the top-1,000 need hand-writing? (Suspect: hand-write the top 200, model the rest.)
3. Account/sync in V1, or stay local-only? Local-only ships faster and removes privacy surface. Recommend local-only V1.
4. Naming — *Oshinagaki* is evocative and authentic but unpronounceable for tourists, which is half your market. Consider a short, kana-friendly, App-Store-searchable alternative.

---

## 13. Rough milestones (solo)

| Phase | Duration | Output |
|---|---|---|
| 0. Validation | 2 weeks | Test-set of 50–100 menu photos; benchmark 2–3 VLMs on parse accuracy and cost; go/no-go |
| 1. Core loop | 5 weeks | Capture → parse → result list → item detail. Ugly but working end-to-end. |
| 2. Language layer | 4 weeks | Curated dictionary, furigana rendering, kanji breakdown, ordering mode, offline fallback |
| 3. Polish & monetise | 3 weeks | Dark-first UI, StoreKit tiers, onboarding, history, error states |
| 4. Beta | 3 weeks | TestFlight with 20–30 real users in Japan; fix the parse failures they surface |
| 5. Launch | 2 weeks | App Store submission, ASO, launch on r/LearnJapanese and r/japanlife |

**~4.5 months to launch.** Images and SRS land in a V2 six to eight weeks later.

---

## Appendix — Test set requirements

Collect before writing parsing code. Aim for 50–100 photos spanning:

- Printed vertical menus (縦書き)
- Brush/calligraphic fonts (筆文字)
- Chalkboard daily specials (handwritten, white on black)
- Laminated photo menus (easy case — baseline)
- Wall strips (短冊, individual paper slips)
- Tablet/screen menus (glare, moiré)
- Poor lighting, angled shots, partial glare, motion blur
- Multi-column layouts with prices in a separate column
