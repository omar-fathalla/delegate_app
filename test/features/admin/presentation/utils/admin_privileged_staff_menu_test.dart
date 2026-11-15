import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/presentation/utils/admin_privileged_staff_menu.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

void main() {
  group('privilegedStaffMenuIncludesManageDelegates', () {
    test('super admin and technical support see manage delegates', () {
      expect(
        privilegedStaffMenuIncludesManageDelegates(UserRole.superAdmin),
        isTrue,
      );
      expect(
        privilegedStaffMenuIncludesManageDelegates(UserRole.technicalSupport),
        isTrue,
      );
    });

    test('company admin does not see privileged manage delegates entry', () {
      expect(privilegedStaffMenuIncludesManageDelegates(UserRole.admin), isFalse);
      expect(privilegedStaffMenuIncludesManageDelegates(UserRole.delegate), isFalse);
    });
  });

  testWidgets('header popup shows المناديب — تعديل وإيقاف when included in menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AdminHeader(
            menuItems: [
              const PopupMenuItem<String>(
                value: manageDelegatesMenuValue,
                child: Text(manageDelegatesMenuTitleAr),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text(manageDelegatesMenuTitleAr), findsOneWidget);
    expect(find.textContaining('تعديل وإيقاف'), findsOneWidget);
  });
}