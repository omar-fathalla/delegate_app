import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/features/admin/presentation/pages/anti_fraud_audit_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_device_unbind_requests_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_monthly_payroll_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_delegates_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_photos_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_top_bar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/tracking/presentation/pages/delegate_tracking_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';

class HRMainScreen extends StatefulWidget {
  final Delegate delegate;

  const HRMainScreen({super.key, required this.delegate});

  @override
  State<HRMainScreen> createState() => _HRMainScreenState();
}

class _HRMainScreenState extends State<HRMainScreen> {
  int _currentIndex = 0;
  final Set<int> _loadedTabs = {0};
  bool _isSidebarExpanded = true;

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

  void _onMenuSelected(String value) {
    final delegate = widget.delegate;

    switch (value) {
      case 'profile':
        context.push('/user-profile', extra: delegate);
        break;
      case 'delegate_tracking':
        _onTabSelected(1);
        break;
      case 'device_unbind_requests':
        _onTabSelected(2);
        break;
      case 'leaves_and_excuses':
        _onTabSelected(3);
        break;
      case 'monthly_payroll':
        _onTabSelected(4);
        break;
      case 'attendance_adjustments':
        _onTabSelected(8);
        break;
      case 'logout':
        _showLogoutDialog(context);
        break;
      case 'settings':
        // Policy: Settings MUST always be the last item in the menu
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              delegate: delegate,
              showAppBar: true,
            ),
          ),
        );
        break;
    }
  }

  void _showLogoutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.logout_rounded, color: colorScheme.error, size: 24),
            const SizedBox(width: 8),
            Text(l10n.logout),
          ],
        ),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'إلغاء',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              context.go('/login');
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    return [
      PopupMenuItem(
        value: 'profile',
        child: Row(
          children: [
            Icon(Icons.person_outline_rounded,
                color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Text(l10n.profile),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'attendance_adjustments',
        child: Row(
          children: [
            Icon(Icons.history_edu_rounded,
                color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            const Text('سجل تعديلات الحضور'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'logout',
        child: Row(
          children: [
            Icon(Icons.logout_rounded, color: colorScheme.error, size: 20),
            const SizedBox(width: 12),
            Text(l10n.logout, style: TextStyle(color: colorScheme.error)),
          ],
        ),
      ),
      const PopupMenuDivider(),
      // Rule: Settings MUST ALWAYS BE THE LAST ITEM in the menu
      PopupMenuItem(
        value: 'settings',
        child: Row(
          children: [
            Icon(Icons.settings_outlined,
                color: colorScheme.onSurfaceVariant, size: 20),
            const SizedBox(width: 12),
            Text(l10n.settings),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final delegate = widget.delegate;

    final isWideScreen = MediaQuery.of(context).size.width > 768;
    final isArabic = localeProvider.isArabic;
    final menuItems = _buildMenuItems(context, l10n, colorScheme);

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: isWideScreen
            ? null
            : UniversalAppHeader(
                delegate: delegate,
                onMenuSelected: _onMenuSelected,
                menuItems: menuItems,
              ),
        body: isWideScreen
            ? Row(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  HRDesktopSidebar(
                    delegate: delegate,
                    selectedIndex: _currentIndex,
                    isExpanded: _isSidebarExpanded,
                    onToggleExpanded: () {
                      setState(() => _isSidebarExpanded = !_isSidebarExpanded);
                    },
                    onItemSelected: _onTabSelected,
                    onOpenProfile: () => _onMenuSelected('profile'),
                    onOpenSettings: () => _onMenuSelected('settings'),
                    onLogout: () => _onMenuSelected('logout'),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        HRDesktopTopBar(
                          delegate: delegate,
                          activeIndex: _currentIndex,
                          onRefresh: () => setState(() {}),
                          onMenuSelected: _onMenuSelected,
                          menuItems: menuItems,
                        ),
                        Expanded(
                          child: _buildIndexedStack(delegate),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : _buildIndexedStack(delegate),
        bottomNavigationBar: isWideScreen
            ? null
            : NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: _onTabSelected,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.how_to_reg_outlined),
                    selectedIcon: Icon(Icons.how_to_reg_rounded),
                    label: 'الحضور',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.radar_outlined),
                    selectedIcon: Icon(Icons.radar_rounded),
                    label: 'الخريطة',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.phonelink_lock_outlined),
                    selectedIcon: Icon(Icons.phonelink_lock_rounded),
                    label: 'الأجهزة',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.event_note_outlined),
                    selectedIcon: Icon(Icons.event_note_rounded),
                    label: 'الطلبات',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                    label: 'الرواتب',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.security_outlined),
                    selectedIcon: Icon(Icons.security_rounded),
                    label: 'الاحتيال',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.photo_library_outlined),
                    selectedIcon: Icon(Icons.photo_library_rounded),
                    label: 'الميداني',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.badge_outlined),
                    selectedIcon: Icon(Icons.badge_rounded),
                    label: 'المناديب',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildIndexedStack(Delegate delegate) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        HRAttendanceTab(
          hrDelegate: delegate,
          onNavigateToTab: _onTabSelected,
        ),
        _loadedTabs.contains(1)
            ? DelegateTrackingScreen(
                adminDelegate: delegate,
                initialMapView: true,
                showAppBar: false,
              )
            : const SizedBox.shrink(),
        _loadedTabs.contains(2)
            ? HRDeviceUnbindRequestsScreen(
                hrDelegate: delegate,
                showAppBar: false,
              )
            : const SizedBox.shrink(),
        _loadedTabs.contains(3)
            ? HRLeavesAndExcusesScreen(
                hrDelegate: delegate,
                showAppBar: false,
              )
            : const SizedBox.shrink(),
        _loadedTabs.contains(4)
            ? HRMonthlyPayrollScreen(
                hrDelegate: delegate,
                showAppBar: false,
              )
            : const SizedBox.shrink(),
        _loadedTabs.contains(5)
            ? AntiFraudAuditScreen(
                delegate: delegate,
                showAppBar: false,
                initialTab: 'violations',
              )
            : const SizedBox.shrink(),
        _loadedTabs.contains(6)
            ? HRPhotosTab(hrDelegate: delegate)
            : const SizedBox.shrink(),
        _loadedTabs.contains(7)
            ? HRDelegatesTab(hrDelegate: delegate)
            : const SizedBox.shrink(),
        _loadedTabs.contains(8)
            ? HRAttendanceAdjustmentsScreen(
                hrDelegate: delegate,
                showAppBar: false,
              )
            : const SizedBox.shrink(),
      ],
    );
  }
}
