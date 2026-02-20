## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2026-06-21 - [Localization] MaterialLocalizations and Tooltips
**Learning:** `MaterialLocalizations` does not always expose standard tooltip strings like `showPasswordTooltip` in older Flutter versions (or they are named differently).
**Action:** Verify availability of localized strings in `MaterialLocalizations` before usage, or use `AppLocalizations` to ensure consistent and safe access to standard UI strings.

## 2026-06-21 - [Forms] Keyboard Actions
**Learning:** Users expect the "Next" action on mobile number fields and "Done" (submit) on password fields to streamline the login flow.
**Action:** Always set `textInputAction: TextInputAction.next` on intermediate fields and `TextInputAction.done` with `onFieldSubmitted` on the final field to match user expectations.
