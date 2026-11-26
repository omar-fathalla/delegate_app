---
name: m3-review
description: Review a screen, component, or m3.material.io page of the Tashil delegate app / HR web against the numbered M3 catalog (docs/design/m3-catalog.md) and the rules (docs/design/design-system.md), then fix in place and report. Use when asked to review a page's design, compare it with M3 or the design system, apply an M3 page, or clean up a screen's hand-written colours and sizes.
---

# m3-review

Talk to the user in Egyptian Arabic. Keep technical terms, file names and code in English.

The catalog (`docs/design/m3-catalog.md`) is the index and its "How to review an
M3 page" section is the full procedure. `docs/design/README.md` says how this app
differs from the original m3-kit (purple seed, no POS items, playground without the POS tab,
`material_ui`).

## Reviewing an app screen (TAS-345 pages)
1. Before photos: the M31 (`adb`, dev build, the fake delegate account) or the
   simulator, every state the screen has. Save them next to the Linear issue.
2. List every element on the screen and match it to a catalog ID (F / C). Mark
   each: matches / differs / missing / does not apply.
3. Start from the matching example in the playground
   (`lib/features/playground/sections/`, open it on the device from Settings in
   a dev build) and copy its setup, so the screen matches what the design
   system shows. Fix in place, official Flutter/Google widget first, then
   `lib/core/design/widgets/`. Colours from roles or `TashilSemanticColors`,
   text from `textTheme`, spacing from `TashilSpacing`, shapes from
   `TashilRadius`, `EdgeInsetsDirectional`.
   Icons on cards: `primary` fill + `onPrimary` icon, `IconButton.filled`
   for icon buttons, never `primaryContainer` / `secondaryContainer`
   (TAS-384). Read-only values are icon + text labels, not chips.
4. Lower the baselines in `test/design/no_new_raw_styles_test.dart` to the new
   counts in the same change.
5. Tests for every behaviour changed, `dart analyze` clean, goldens updated and
   checked by eye.
6. After photos with the same account, data and theme mode; attach before/after
   to the Linear issue with the table (ID, element, before, after).
7. Update the catalog row (Code, Test, Reviewed date) when a component moves.

## Reviewing an m3.material.io page
1. Read the whole page, every tab, in a real browser (the site is JS-rendered).
2. List every component, measurement, behaviour, do and don't.
3. Match each to a catalog ID. matches: update the Reviewed date only. differs:
   update in place, same ID. missing: new row with the next ID. does not apply:
   note why. Official Flutter/Google widgets first; hand-built only when none
   exists, marked "hand-built" in the catalog.
4. Tests, analyze, and the rule in `docs/design/design-system.md`.
5. Report a table: ID, item, result, one line why. Mark assumptions.
