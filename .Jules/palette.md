## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-05-24 - [Forms] Checkbox Tap Targets
**Learning:** Checkboxes alone have too small of a touch target, particularly on mobile devices. Users naturally try to tap the associated text label.
**Action:** Always make checkbox labels tappable by wrapping the `Checkbox` and `Text` (usually inside a `Row` with `mainAxisSize: MainAxisSize.min`) in an `InkWell` or `GestureDetector` that toggles the checkbox state.
