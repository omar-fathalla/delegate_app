1. **Update `lib/l10n/app_en.arb`**
   - Use `replace_with_git_merge_diff` to add `"showPassword": "Show password"` and its description metadata to `lib/l10n/app_en.arb`.
   - Also add `"hidePassword": "Hide password"` and its description metadata to the same file.

2. **Update `lib/l10n/app_ar.arb`**
   - Use `replace_with_git_merge_diff` to add `"showPassword": "عرض كلمة المرور"` and its description metadata to `lib/l10n/app_ar.arb`.
   - Also add `"hidePassword": "إخفاء كلمة المرور"` and its description metadata to the same file.

3. **Generate Localization Files**
   - Run `flutter gen-l10n` to regenerate `lib/l10n/app_localizations.dart` and the respective `en` and `ar` files.
   - Run `grep -n "showPassword" lib/l10n/app_localizations.dart` to verify generation.

4. **Modify `login_screen.dart` to add tooltips**
   - Use `replace_with_git_merge_diff` on `lib/features/auth/presentation/pages/login_screen.dart` to update the `IconButton` that toggles password visibility. Add the `tooltip` property to it: `tooltip: _obscurePassword ? l10n.showPassword : l10n.hidePassword`.

5. **Modify `user_profile_screen.dart` to add tooltips**
   - Use `replace_with_git_merge_diff` on `lib/features/profile/presentation/pages/user_profile_screen.dart` to add the `tooltip` property to the `IconButton` in the `_buildTextField` method. Because `l10n` is not available in that widget method by default, we'll get it directly inside `_buildTextField` via `final l10n = AppLocalizations.of(context)!;` or use it in `IconButton`. Wait, `_buildTextField` doesn't have `context` passed directly if it's outside `build`, but it is a member function of `_ChangePasswordBottomSheetState` and can access `context`. So, `tooltip: obscureText ? AppLocalizations.of(context)!.showPassword : AppLocalizations.of(context)!.hidePassword`.

6. **Format and Analyze Code**
   - Run `dart format lib/features/auth/presentation/pages/login_screen.dart lib/features/profile/presentation/pages/user_profile_screen.dart`.
   - Run `flutter analyze` to ensure there are no static analysis issues.

7. **Run Tests**
   - Run `flutter test` to ensure no tests were broken by this change.

8. **Add Journal Entry**
   - Use bash `cat << 'EOF' >> .Jules/palette.md` to append a journal entry about using dynamic tooltips (`tooltip: obscureText ? l10n.showPassword : l10n.hidePassword`) for password visibility toggles to improve screen reader accessibility.

9. **Complete Pre-Commit Steps**
   - Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done.

10. **Submit PR**
    - Use the PR title `🎨 Palette: Add accessibility tooltips to password visibility toggles` and description format containing `💡 What`, `🎯 Why`, `📸 Before/After`, and `♿ Accessibility`.
