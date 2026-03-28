## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.
## 2026-03-28 - [Accessibility] Added Tooltips to IconButtons
**Learning:** Icon-only buttons (like password visibility toggles, close dialog buttons, and browser links) lacked tooltips, which made them inaccessible to screen readers and difficult to understand without context.
**Action:** Consistently use the `tooltip` property on `IconButton` widgets. Prefer built-in semantic labels like `MaterialLocalizations.of(context).backButtonTooltip` for standard actions, and add custom translations to `.arb` files for specific actions like "Show Password".
