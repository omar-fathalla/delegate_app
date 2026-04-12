## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2024-04-12 - Accessibility: Toggle Password Tooltips
**Learning:** Icon-only buttons used for password visibility toggling (`visibility_off_outlined`/`visibility_outlined`) need explicit tooltips explaining their function to users, especially since the state toggles and the tooltip should reflect the action ("Show password" vs "Hide password").
**Action:** When creating password input fields, always supply the `tooltip` argument on the `IconButton` suffix icon using localizations, and verify it updates dynamically alongside the visibility state to maintain accessibility.
