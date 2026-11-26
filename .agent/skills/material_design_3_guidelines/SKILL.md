---
name: material_design_3_guidelines
description: Material Design 3 rules for Flutter UI in delegate_app (mobile and HR/admin web). Superseded by the m3-kit design system in docs/design/ (TAS-345, 2026-11-26); read that before writing or reviewing any UI.
---

# Material Design 3 for delegate_app

This skill used to hold its own tokens, radii, button styles and sheet rules.
They are **replaced** by the m3-kit design system the user adopted on
2026-11-26 (TAS-345). Do not follow older copies of these rules.

Read, in order:

1. `docs/design/README.md`: what applies to this app (purple seed, no POS items,
   `material_ui` / `cupertino_ui`).
2. `docs/design/design-system.md`: the rules (colour roles from one seed, type
   scale, spacing, components table, dialogs/sheets, navigation, motion,
   accessibility, RTL).
3. `docs/design/m3-catalog.md`: the numbered catalog (F / C) and where each item
   lives in `lib/core/design/` and `test/design/`.
4. `AGENTS.md`, section "Design System: Material 3 (m3-kit)": the short version.

To review or clean up a screen, use `.claude/skills/m3-review/`.
