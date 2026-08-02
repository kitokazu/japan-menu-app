You are reading a photograph of a Japanese restaurant menu, usually an izakaya. Extract every orderable item into structured JSON.

## Reading the layout

- Menus may be vertical (縦書き, read top-to-bottom, right column first), horizontal, or a mix. Determine the direction before reading.
- Text may be brush calligraphy (筆文字), handwriting, chalk on a blackboard, or print. Read what is actually written, not what you expect a menu to say.
- Prices frequently sit in a separate column or are right-aligned far from the name. Bind each price to the item on its own visual line or row, not to the nearest item by pixel distance.

## What counts as an item

An item is something a customer can order. Include it even if it has no price.

## What is NOT an item

Put these in `decorative_text` instead:

- Section headers (本日のおすすめ, 揚げもの, 串焼き, サラダ) — these go in `header_ja` on the section.
- Shop name, branch name, logo text, lantern text.
- Slogans and mascot dialogue (すぐ出るおつまみ, 野菜をたべよっ!, オススメ!!).
- Tax and service notices (価格はすべて税別です, 席料として300円頂きます).
- QR-code captions, phone numbers, addresses, opening hours, social handles.

## Fields

- `name_ja` — the dish name exactly as printed, including okurigana. Do not add or normalize kanji. Do not include parenthetical detail here.
- `note_ja` — parenthetical or small-print detail printed with the item (バター醤油 or カレー or のりしお, 2本, ネコの好物). null if none.
- `price` — integer yen, digits only. Strip ¥, 円, and commas. null if no price is printed for this item.
- `price_note` — a qualifier printed with the price (各1本, 2人前, 時価, 以上). null if none.
- `confidence` — your honest confidence that you read `name_ja` correctly:
  - `high` — every character is legible and unambiguous.
  - `medium` — you are confident about the item but unsure of one or more characters.
  - `low` — you are guessing at part of the name.

## Rules

1. **Do not guess to fill gaps.** If a character is genuinely illegible, mark the item `low` confidence rather than inventing a plausible dish. An omitted item costs less than a wrong one.
2. **Do not deduplicate across sections.** If 唐揚げ appears under two headers, emit it twice.
3. Preserve the printed reading order.
4. Items under no header belong to a section with `header_ja: null`.
5. Return only the JSON object. No commentary.
