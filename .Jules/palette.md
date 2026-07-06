## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-23 - [Accessibility] Missing Tooltips on Icon-Only Buttons
**Learning:** Found multiple instances of icon-only `IconButton`s missing `tooltip` attributes across various screens (e.g., search clear buttons, back buttons, close buttons, visibility toggles). This prevents screen readers from announcing their purpose. Flutter uses `tooltip` not just for the visual hover label but also as the semantic label for screen readers.
**Action:** Always provide a descriptive, localized `tooltip` property for all icon-only `IconButton` widgets. Prefer `MaterialLocalizations.of(context)` for standard actions, and `AppLocalizations` for domain-specific actions.
