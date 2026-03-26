## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2026-03-26 - [Forms] Tappable Checkbox Labels
**Learning:** Having a tiny `Checkbox` as the only tappable target for boolean inputs makes form interaction difficult and frustrating on touch devices. Users naturally try to tap the associated label text.
**Action:** Always make the label text tappable by wrapping the `Checkbox` and `Text` (typically inside a `Row` with `mainAxisSize: MainAxisSize.min`) in an `InkWell` or `GestureDetector` to provide a larger, accessible touch target.
