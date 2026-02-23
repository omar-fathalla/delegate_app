## 2026-02-16 - [Attendance] Missing Tooltips on Navigation Buttons
**Learning:** The month navigation and scanner close buttons lacked `tooltip` descriptions. This made it difficult for screen reader users to understand the purpose of these icon-only buttons.
**Action:** When using `IconButton`, always provide a `tooltip` property to describe the action, especially for navigation arrows and close buttons.

## 2024-05-22 - [Auth] Password Visibility Toggle
**Learning:** Obscured text fields without a visibility toggle frustrate users who need to verify complex passwords or names.
**Action:** Always include a suffix icon toggle for `obscureText` fields, ensuring the icon state (eye vs slashed eye) matches the *action* (Show vs Hide) or *state* (Visible vs Hidden) consistently with the design system.

## 2026-03-02 - [Auth] Form Keyboard Navigation
**Learning:** Users expect the "Enter" key (or "Done" action) on the last form field to submit the form, and "Next" to move to the next field.
**Action:** Always configure `textInputAction` on `TextFormField`s (`next` for intermediate, `done` for last) and use `onFieldSubmitted` on the final field to trigger the submit action.
