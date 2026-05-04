## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.
## 2024-05-17 - Added Tooltips to Icon-Only Password Toggle
**Learning:** Icon-only buttons without tooltips are a common accessibility issue. For password toggle buttons, providing an accessible label ("Show password" / "Hide password") is important for screen reader compatibility and general usability. This pattern needs localized strings.
**Action:** Added `showPassword` and `hidePassword` to `.arb` files and used them as `tooltip` in `IconButton` across the app where passwords can be toggled.
