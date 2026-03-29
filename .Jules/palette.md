## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-11-06 - [A11y] Icon-only Password Visibility Toggles
**Learning:** Icon-only buttons used for password visibility toggles lack context for screen readers if they don't have descriptive tooltips. Defaulting to standard MaterialLocalizations might not provide the exact meaning required (e.g. 'Show accounts' instead of 'Show password').
**Action:** Always provide explicit, translated `tooltip` properties for icon-only password visibility toggles, using specific app localizations rather than generic defaults to ensure proper accessibility.
