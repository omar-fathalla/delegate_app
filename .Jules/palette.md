## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-11-20 - [Forms] Tappable Checkbox Labels
**Learning:** Checkboxes alone present a tiny hit target, causing friction for users trying to select or deselect an option. When the text label next to a checkbox is not tappable, it can lead to frustrating missed taps, particularly on mobile devices.
**Action:** Always make checkbox labels tappable by wrapping both the `Checkbox` and `Text` (typically inside a `Row` with `mainAxisSize: MainAxisSize.min`) in an `InkWell` (for visual feedback) or `GestureDetector`.
