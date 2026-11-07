import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// M3 [LoginScreen] keys from [login_screen.dart] (Patrol / widget tests).
Finder devLoginStaffModeFinder() =>
    find.byKey(ValueKey('group_item_${LoginMode.staff}'));

Finder devLoginDelegateModeFinder() =>
    find.byKey(ValueKey('group_item_${LoginMode.delegate}'));

Finder devLoginPhoneFieldFinder() =>
    find.byKey(const ValueKey('login_phone'));

Finder devLoginStaffPasswordFieldFinder() =>
    find.byKey(const ValueKey('login_staff_password'));

Finder devLoginDelegateNationalIdFieldFinder() =>
    find.byKey(const ValueKey('login_national_id'));

Finder devLoginSubmitFinder() => find.byKey(const ValueKey('login_submit'));
