import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Indexed-stack slots of the HR shell. 0–8 are the original mobile tabs.
const int kHrTabAttendance = 0;
const int kHrTabTracking = 1;
const int kHrTabDevices = 2;
const int kHrTabLeaves = 3;
const int kHrTabPayroll = 4;
const int kHrTabFraud = 5;
const int kHrTabPhotos = 6;
const int kHrTabDelegates = 7;
const int kHrTabAdjustments = 8;
const int kHrTabSubscriptions = 9;
const int kHrTabRenewal = 10;
const int kHrTabTasks = 11;
const int kHrTabPhotoPermissions = 12;
const int kHrTabPenaltyCatalog = 13;
const int kHrTabPenalties = 14;
const int kHrTabOverview = 15;
const int kHrShellTabCount = 16;

/// The tab `/hr/home` opens on. Web lands on the overview; mobile keeps the
/// attendance tab.
int hrShellHomeTab({required bool isWeb}) =>
    isWeb ? kHrTabOverview : kHrTabAttendance;

/// Where a shell item is rendered.
enum HrShellPlacement { sidebar, compactMenu, moreSheet }

/// One destination of the web HR shell.
///
/// Titles match the company-supervisor mobile menu. On web, [menuLabel] is
/// the one page name (TAS-138): the sidebar, the top bar title and the
/// inner-page breadcrumb all show it. Items that already lived
/// in the HR shell keep their tab index. Tools that only the supervisor menu
/// had are [webOnly] so the mobile HR shell stays as it is.
class HrShellItem {
  final String id;
  final String title;

  /// Shorter label for web menus only (sidebar, collapsed rail, compact
  /// menu, and the web "more" sheet). Null keeps [title]. Mobile menus
  /// never read this.
  final String? webTitle;
  final String subtitle;
  final String section;
  final IconData icon;
  final IconData selectedIcon;
  final int? tabIndex;
  final String? badgeCollection;
  final bool webOnly;
  final bool destructive;
  final bool requiresRenewalPermission;

  const HrShellItem({
    required this.id,
    required this.title,
    this.webTitle,
    required this.subtitle,
    required this.section,
    required this.icon,
    required this.selectedIcon,
    this.tabIndex,
    this.badgeCollection,
    this.webOnly = false,
    this.destructive = false,
    this.requiresRenewalPermission = false,
  });

  /// Menu label. Web uses [webTitle] when one is set; mobile keeps [title].
  String menuLabel({required bool isWeb}) =>
      isWeb ? (webTitle ?? title) : title;
}

const List<HrShellItem> kHrShellCatalog = [
  HrShellItem(
    id: 'overview',
    title: 'الرئيسية',
    subtitle: 'حضور النهاردة والسلاسل',
    section: 'الرئيسية',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    tabIndex: kHrTabOverview,
    webOnly: true,
  ),
  HrShellItem(
    id: 'profile',
    title: 'الملف الشخصي',
    subtitle: 'بيانات الحساب',
    section: 'الحساب',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
  HrShellItem(
    id: 'delegate_subscriptions',
    title: 'طلبات اشتراك واعتماد المناديب',
    webTitle: 'طلبات الاشتراك',
    subtitle: 'اعتماد طلبات تسجيل المناديب واشتراكاتهم',
    section: 'الكوادر والاشتراكات',
    icon: Icons.how_to_reg_outlined,
    selectedIcon: Icons.how_to_reg_rounded,
    tabIndex: kHrTabSubscriptions,
    webOnly: true,
  ),
  HrShellItem(
    id: 'delegate_renewal',
    title: 'تجديد المناديب',
    subtitle: 'تجديد اشتراك مناديب الشركة',
    section: 'الكوادر والاشتراكات',
    icon: Icons.autorenew_outlined,
    selectedIcon: Icons.autorenew_rounded,
    tabIndex: kHrTabRenewal,
    webOnly: true,
    requiresRenewalPermission: true,
  ),
  HrShellItem(
    id: 'attendance',
    title: 'سجل الحضور والانصراف',
    webTitle: 'الحضور والانصراف',
    subtitle: 'متابعة حضور وانصراف مناديب الشركة',
    section: 'الحضور والميدان',
    icon: Icons.event_available_outlined,
    selectedIcon: Icons.event_available_rounded,
    tabIndex: kHrTabAttendance,
  ),
  HrShellItem(
    id: 'delegates',
    title: 'مناديب الشركة',
    subtitle: 'دليل مناديب الشركة',
    section: 'الكوادر والاشتراكات',
    icon: Icons.badge_outlined,
    selectedIcon: Icons.badge_rounded,
    tabIndex: kHrTabDelegates,
  ),
  HrShellItem(
    id: 'delegate_tracking',
    title: 'Live Tracking',
    webTitle: 'الخريطة الحية',
    subtitle: 'المواقع الميدانية اللحظية',
    section: 'الحضور والميدان',
    icon: Icons.radar_outlined,
    selectedIcon: Icons.radar_rounded,
    tabIndex: kHrTabTracking,
  ),
  HrShellItem(
    id: 'field_photos',
    title: 'الصور والزيارات الميدانية',
    webTitle: 'الصور',
    subtitle: 'صور الزيارات وأذونات التصوير',
    section: 'الحضور والميدان',
    icon: Icons.photo_library_outlined,
    selectedIcon: Icons.photo_library_rounded,
    tabIndex: kHrTabPhotos,
  ),
  HrShellItem(
    id: 'supervisor_photo_permissions',
    title: 'أذونات التصوير',
    subtitle: 'اعتماد أذونات التصوير الميداني',
    // Web sidebar: directly under «الصور» in this group.
    section: 'الحضور والميدان',
    icon: Symbols.add_a_photo,
    selectedIcon: Symbols.add_a_photo_rounded,
    tabIndex: kHrTabPhotoPermissions,
    webOnly: true,
  ),
  HrShellItem(
    id: 'attendance_adjustments',
    title: 'سجل تعديلات الحضور والانصراف',
    webTitle: 'تعديلات الحضور',
    subtitle: 'التعديلات اليدوية على البصمات',
    section: 'الحضور والميدان',
    icon: Icons.history_edu_outlined,
    selectedIcon: Icons.history_edu_rounded,
    tabIndex: kHrTabAdjustments,
  ),
  HrShellItem(
    id: 'leaves_and_excuses',
    title: 'طلبات الإجازات والأعذار',
    webTitle: 'طلبات الإجازات',
    subtitle: 'اعتماد الإجازات والأعذار',
    section: 'الطلبات والماليات',
    icon: Icons.event_note_outlined,
    selectedIcon: Icons.event_note_rounded,
    tabIndex: kHrTabLeaves,
    badgeCollection: 'leave_requests',
  ),
  HrShellItem(
    id: 'monthly_payroll',
    title: 'مسير الرواتب والعمولات',
    webTitle: 'الرواتب',
    subtitle: 'كشوف الرواتب والبدلات',
    section: 'الطلبات والماليات',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
    tabIndex: kHrTabPayroll,
  ),
  HrShellItem(
    id: 'anti_fraud',
    title: 'تدقيق الأمان ومكافحة الاحتيال',
    webTitle: 'تدقيق الأمان',
    subtitle: 'محاولات التلاعب بالموقع والجهاز',
    section: 'الرقابة والأدوات',
    icon: Icons.security_outlined,
    selectedIcon: Icons.security_rounded,
    tabIndex: kHrTabFraud,
  ),
  HrShellItem(
    id: 'device_unbind_requests',
    title: 'طلبات فك وربط الأجهزة',
    webTitle: 'فك الأجهزة',
    subtitle: 'طلبات تغيير هاتف المندوب',
    // Web sidebar: الرقابة والأدوات, immediately after تدقيق الأمان.
    section: 'الرقابة والأدوات',
    icon: Icons.phonelink_lock_outlined,
    selectedIcon: Icons.phonelink_lock_rounded,
    tabIndex: kHrTabDevices,
    badgeCollection: 'device_unbind_requests',
  ),
  HrShellItem(
    id: 'tasks',
    title: 'المهام',
    subtitle: 'مهام المناديب ومتابعتها',
    section: 'الرقابة والأدوات',
    icon: Icons.task_alt_outlined,
    selectedIcon: Icons.task_alt_rounded,
    tabIndex: kHrTabTasks,
    webOnly: true,
  ),
  HrShellItem(
    id: 'penalty_rules_catalog',
    title: 'لائحة الغرامات والجزاءات',
    webTitle: 'لائحة الغرامات',
    subtitle: 'اللائحة المعتمدة للجزاءات',
    section: 'الرقابة والأدوات',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book_rounded,
    tabIndex: kHrTabPenaltyCatalog,
    webOnly: true,
  ),
  HrShellItem(
    id: 'penalties_management',
    title: 'نظام الغرامات والمخالفات',
    webTitle: 'نظام الغرامات',
    subtitle: 'إصدار ومتابعة الغرامات',
    section: 'الرقابة والأدوات',
    icon: Icons.gavel_outlined,
    selectedIcon: Icons.gavel_rounded,
    tabIndex: kHrTabPenalties,
    webOnly: true,
    destructive: true,
  ),
  HrShellItem(
    id: 'settings',
    title: 'الإعدادات',
    subtitle: 'إعدادات الحساب',
    section: 'الإعدادات',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
];

/// Tabs of the compact bottom bar, in order. On web the first slot is the
/// overview, so the attendance log moves into the "more" sheet.
List<int> hrBottomNavTabs({required bool isWeb}) => [
  isWeb ? kHrTabOverview : kHrTabAttendance,
  kHrTabDelegates,
  kHrTabTracking,
  kHrTabLeaves,
];

HrShellItem? hrShellItemById(String id) {
  for (final item in kHrShellCatalog) {
    if (item.id == id) return item;
  }
  return null;
}

/// Items shown on one surface of the web shell.
///
/// Renewal stays hidden unless [canCreateSubscriptionRenewal] allows it, the
/// same rule as the supervisor menu. On web the profile row is not in the
/// sidebar (the header account button opens it). Settings stay in the footer
/// and at the end of the compact menu. The compact "more" sheet skips the
/// four bottom-nav tabs.
List<HrShellItem> hrShellItems({
  required Delegate delegate,
  required bool isWeb,
  required HrShellPlacement placement,
}) {
  final visible = <HrShellItem>[];
  for (final item in kHrShellCatalog) {
    if (item.webOnly && !isWeb) continue;
    if (item.requiresRenewalPermission &&
        !canCreateSubscriptionRenewal(
          role: delegate.role,
          companyUID: delegate.companyUID,
        )) {
      continue;
    }
    final show = switch (placement) {
      HrShellPlacement.sidebar =>
        item.id != 'settings' && !(isWeb && item.id == 'profile'),
      HrShellPlacement.compactMenu => true,
      HrShellPlacement.moreSheet =>
        item.id != 'profile' &&
            item.id != 'settings' &&
            (item.tabIndex == null ||
                !hrBottomNavTabs(isWeb: isWeb).contains(item.tabIndex)),
    };
    if (show) visible.add(item);
  }
  return visible;
}

String hrShellHeaderTitle(int index) {
  for (final item in kHrShellCatalog) {
    if (item.tabIndex == index) return item.title;
  }
  return 'بوابة الموارد البشرية';
}

/// Short page name of a shell tab: the sidebar label on web, the full title
/// on mobile. Used as the first breadcrumb item of inner pages.
String hrShellPageLabel(int index, {required bool isWeb}) {
  for (final item in kHrShellCatalog) {
    if (item.tabIndex == index) return item.menuLabel(isWeb: isWeb);
  }
  return 'الرئيسية';
}

IconData hrShellHeaderIcon(int index) {
  for (final item in kHrShellCatalog) {
    if (item.tabIndex == index) return item.selectedIcon;
  }
  return Icons.business_center_rounded;
}
