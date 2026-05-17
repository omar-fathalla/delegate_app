## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-23 - [A11y] Native tooltips vs custom keys
**Learning:** When adding tooltips to standard navigation buttons (like back arrows or close buttons), it's unnecessary to create custom translation keys in `.arb` files.
**Action:** Prefer using Flutter's built-in `MaterialLocalizations.of(context).backButtonTooltip` or `closeButtonTooltip` which provide localized standard accessibility labels automatically. Custom keys are only needed for custom domain-specific actions (like 'Show Password').
