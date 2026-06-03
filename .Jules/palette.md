## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.
## 2026-02-16 - [A11y] Missing Tooltips on Icon-Only Navigation & Control Buttons
**Learning:** Found several top-level navigation and control `IconButton`s (like close, back, logout, and filter) lacking `tooltip` properties. This leaves screen reader users without crucial context. Flutter's `MaterialLocalizations` provides excellent out-of-the-box tooltips for standard actions (like `backButtonTooltip` and `closeButtonTooltip`), while custom app actions need localized string tooltips.
**Action:** Consistently leverage `MaterialLocalizations.of(context)` for standard UI button tooltips and explicit localized strings for custom actions to ensure accessible semantic labels for icon-only buttons.
