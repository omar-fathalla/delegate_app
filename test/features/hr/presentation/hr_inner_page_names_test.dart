import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/l10n/app_localizations_ar.dart';

/// TAS-138: one name per page on web (sidebar = top bar = breadcrumb) and
/// one HR role name.
void main() {
  test('web page names come from one table', () {
    const expected = {
      kHrTabOverview: 'الرئيسية',
      kHrTabSubscriptions: 'طلبات الاشتراك',
      kHrTabRenewal: 'تجديد المناديب',
      kHrTabAttendance: 'الحضور والانصراف',
      kHrTabDelegates: 'مناديب الشركة',
      kHrTabTracking: 'الخريطة الحية',
      kHrTabPhotos: 'الصور',
      // TAS-149: the retired permissions slot resolves to «الصور».
      kHrTabPhotoPermissions: 'الصور',
      kHrTabAdjustments: 'تعديلات الحضور',
      kHrTabLeaves: 'طلبات الإجازات',
      kHrTabPayroll: 'الرواتب',
      kHrTabFraud: 'تدقيق الأمان',
      kHrTabDevices: 'فك الأجهزة',
      kHrTabTasks: 'المهام',
      kHrTabPenaltyCatalog: 'لائحة الغرامات',
      kHrTabPenalties: 'نظام الغرامات',
    };
    expected.forEach((tab, name) {
      expect(hrShellPageLabel(tab, isWeb: true), name, reason: '$tab');
    });
  });

  test('HR role has one Arabic name', () {
    final ar = AppLocalizationsAr();
    expect(ar.roleHrOfficer, ar.roleHr);
  });
}
