import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/features/admin/presentation/pages/subscription_renewal_screen.dart';
import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_top_bar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_more_bottom_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';

class HRMainScreen extends StatefulWidget {
  final Delegate delegate;
  final int initialIndex;

  const HRMainScreen({
    super.key,
    required this.delegate,
    this.initialIndex = 0,
  });

  @override
  State<HRMainScreen> createState() => _HRMainScreenState();
}

class _HRMainScreenState extends State<HRMainScreen> {
  late int _currentIndex;
  late final Set<int> _loadedTabs;
  bool _isSidebarExpanded = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadedTabs = {widget.initialIndex};
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

  /// تحويل مؤشر التبويب النشط إلى موقعه في الشريط السفلي للموبايل (4 أساسية + المزيد)
  int _getBottomNavIndex(int currentTabIndex) {
    switch (currentTabIndex) {
      case 0:
        return 0; // الحضور
      case 7:
        return 1; // المناديب
      case 1:
        return 2; // الخريطة
      case 3:
        return 3; // الطلبات
      default:
        return 4; // المزيد (الرواتب: 4, الأجهزة: 2, الاحتيال: 5, الميداني: 6, تعديلات الحضور: 8)
    }
  }

  /// التفاعل مع عناصر الشريط السفلي للموبايل
  void _onBottomNavSelected(int bottomNavIndex) {
    switch (bottomNavIndex) {
      case 0:
        _onTabSelected(0); // الحضور
        break;
      case 1:
        _onTabSelected(7); // المناديب
        break;
      case 2:
        _onTabSelected(1); // الخريطة
        break;
      case 3:
        _onTabSelected(3); // الطلبات
        break;
      case 4:
        _showMoreBottomSheet(context);
        break;
    }
  }

  /// فتح النافذة السفلية المنبثقة Material 3 لقائمة "المزيد"
  void _showMoreBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => HRMoreBottomSheet(
        hrDelegate: widget.delegate,
        currentIndex: _currentIndex,
        onSelectTab: _onTabSelected,
      ),
    );
  }

  /// شارة طلبات الإجازات والأذونات المعلقة
  Widget _buildLeaveRequestsBadge(Widget icon, ColorScheme colorScheme) {
    if (widget.delegate.companyUID.isEmpty) return icon;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leave_requests')
          .where('companyUID', isEqualTo: widget.delegate.companyUID)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return icon;
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return icon;
        return Badge(
          label: Text(
            '$count',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          backgroundColor: colorScheme.error,
          textColor: colorScheme.onError,
          child: icon,
        );
      },
    );
  }

  /// شارة طلبات فك وربط الأجهزة المعلقة
  Widget _buildDeviceRequestsBadge(Widget icon, ColorScheme colorScheme) {
    if (widget.delegate.companyUID.isEmpty) return icon;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('device_unbind_requests')
          .where('companyUID', isEqualTo: widget.delegate.companyUID)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return icon;
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return icon;
        return Badge(
          label: Text(
            '$count',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          backgroundColor: colorScheme.error,
          textColor: colorScheme.onError,
          child: icon,
        );
      },
    );
  }

  void _onMenuSelected(String value) {
    final delegate = widget.delegate;

    switch (value) {
      case 'profile':
        context.push('/user-profile', extra: delegate);
        break;
      case 'attendance':
        _onTabSelected(0);
        break;
      case 'delegates':
        _onTabSelected(7);
        break;
      case 'delegate_tracking':
        _onTabSelected(1);
        break;
      case 'leaves_and_excuses':
        _onTabSelected(3);
        break;
      case 'monthly_payroll':
        _onTabSelected(4);
        break;
      case 'device_unbind_requests':
        _onTabSelected(2);
        break;
      case 'anti_fraud':
        _onTabSelected(5);
        break;
      case 'field_photos':
        _onTabSelected(6);
        break;
      case 'attendance_adjustments':
        _onTabSelected(8);
        break;
      case 'delegate_subscriptions':
      case 'tasks':
      case 'supervisor_photo_permissions':
      case 'penalty_rules_catalog':
      case 'penalties_management':
        final tab = hrShellItemById(value)?.tabIndex;
        if (tab != null) _onTabSelected(tab);
        break;
      case 'delegate_renewal':
        if (WebRuntimePolicy.isWeb) {
          _onTabSelected(kHrTabRenewal);
          break;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubscriptionRenewalScreen(supervisor: delegate),
          ),
        );
        break;
      case 'logout':
        _showLogoutDialog(context);
        break;
      case 'settings':
        // Policy: Settings MUST always be the last item in the menu
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                SettingsScreen(delegate: delegate, showAppBar: true),
          ),
        );
        break;
    }
  }

  void _showLogoutDialog(BuildContext context) {
    AppLogoutModal.show(context, delegate: widget.delegate);
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    PopupMenuItem<String> buildMenuItem({
      required String value,
      required Widget icon,
      required String title,
      Color? color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            SizedBox(width: 24, height: 24, child: Center(child: icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (WebRuntimePolicy.isWeb) {
      final entries = <PopupMenuEntry<String>>[];
      for (final item in hrShellItems(
        delegate: widget.delegate,
        isWeb: true,
        placement: HrShellPlacement.compactMenu,
      )) {
        if (item.id == 'settings') entries.add(const PopupMenuDivider());
        final icon = item.badgeCollection == 'leave_requests'
            ? _buildLeaveRequestsBadge(
                Icon(item.selectedIcon, color: colorScheme.primary, size: 20),
                colorScheme,
              )
            : item.badgeCollection == 'device_unbind_requests'
            ? _buildDeviceRequestsBadge(
                Icon(item.selectedIcon, color: colorScheme.primary, size: 20),
                colorScheme,
              )
            : Icon(
                item.selectedIcon,
                color: item.destructive
                    ? colorScheme.error
                    : item.id == 'delegate_renewal'
                    ? colorScheme.tertiary
                    : colorScheme.primary,
                size: 20,
              );
        entries.add(
          buildMenuItem(
            value: item.id,
            icon: icon,
            title: item.title,
            color: item.destructive ? colorScheme.error : null,
          ),
        );
      }
      return entries;
    }

    return [
      buildMenuItem(
        value: 'profile',
        icon: Icon(
          Icons.person_outline_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
        title: l10n.profile,
      ),
      buildMenuItem(
        value: 'attendance',
        icon: Icon(
          Icons.how_to_reg_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
        title: 'الحضور والانصراف',
      ),
      buildMenuItem(
        value: 'delegates',
        icon: Icon(Icons.badge_rounded, color: colorScheme.primary, size: 20),
        title: 'مناديب الشركة',
      ),
      buildMenuItem(
        value: 'delegate_tracking',
        icon: Icon(Icons.radar_rounded, color: colorScheme.primary, size: 20),
        title: 'Live Tracking',
      ),
      buildMenuItem(
        value: 'leaves_and_excuses',
        icon: _buildLeaveRequestsBadge(
          Icon(Icons.event_note_rounded, color: colorScheme.primary, size: 20),
          colorScheme,
        ),
        title: 'طلبات الإجازات والأعذار',
      ),
      buildMenuItem(
        value: 'monthly_payroll',
        icon: Icon(
          Icons.account_balance_wallet_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
        title: 'مسير الرواتب والعمولات',
      ),
      buildMenuItem(
        value: 'device_unbind_requests',
        icon: _buildDeviceRequestsBadge(
          Icon(
            Icons.phonelink_lock_rounded,
            color: colorScheme.primary,
            size: 20,
          ),
          colorScheme,
        ),
        title: 'طلبات فك وربط الأجهزة',
      ),
      buildMenuItem(
        value: 'anti_fraud',
        icon: Icon(
          Icons.security_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
        title: 'تدقيق الأمان ومكافحة الاحتيال',
      ),
      buildMenuItem(
        value: 'field_photos',
        icon: Icon(
          Icons.photo_library_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
        title: 'الصور والزيارات الميدانية',
      ),
      buildMenuItem(
        value: 'attendance_adjustments',
        icon: Icon(
          Icons.history_edu_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
        title: 'سجل تعديلات الحضور والانصراف',
      ),
      if (canCreateSubscriptionRenewal(
        role: widget.delegate.role,
        companyUID: widget.delegate.companyUID,
      ))
        buildMenuItem(
          value: 'delegate_renewal',
          icon: Icon(
            Icons.autorenew_rounded,
            color: colorScheme.tertiary,
            size: 20,
          ),
          title: SubscriptionRenewalScreen.title,
        ),
      const PopupMenuDivider(),
      // Rule: Settings MUST ALWAYS BE THE LAST ITEM in the menu
      buildMenuItem(
        value: 'settings',
        icon: Icon(
          Icons.settings_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 20,
        ),
        title: l10n.settings,
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
      child: PopScope(
        canPop: isWideScreen || _currentIndex == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_currentIndex != 0) {
            _onTabSelected(0);
          }
        },
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
                  textDirection: isArabic
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: [
                    HRDesktopSidebar(
                      delegate: delegate,
                      selectedIndex: _currentIndex,
                      isExpanded: _isSidebarExpanded,
                      onToggleExpanded: () {
                        setState(
                          () => _isSidebarExpanded = !_isSidebarExpanded,
                        );
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
                          Expanded(child: _buildIndexedStack(delegate)),
                        ],
                      ),
                    ),
                  ],
                )
              : _buildIndexedStack(delegate),
          bottomNavigationBar: isWideScreen
              ? null
              : NavigationBar(
                  selectedIndex: _getBottomNavIndex(_currentIndex),
                  onDestinationSelected: _onBottomNavSelected,
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.how_to_reg_outlined),
                      selectedIcon: Icon(Icons.how_to_reg_rounded),
                      label: 'الحضور',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.badge_outlined),
                      selectedIcon: Icon(Icons.badge_rounded),
                      label: 'المناديب',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.radar_outlined),
                      selectedIcon: Icon(Icons.radar_rounded),
                      label: 'الخريطة',
                    ),
                    NavigationDestination(
                      icon: _buildLeaveRequestsBadge(
                        const Icon(Icons.event_note_outlined),
                        colorScheme,
                      ),
                      selectedIcon: _buildLeaveRequestsBadge(
                        const Icon(Icons.event_note_rounded),
                        colorScheme,
                      ),
                      label: 'الطلبات',
                    ),
                    NavigationDestination(
                      icon: _buildDeviceRequestsBadge(
                        const Icon(Icons.grid_view_outlined),
                        colorScheme,
                      ),
                      selectedIcon: _buildDeviceRequestsBadge(
                        const Icon(Icons.grid_view_rounded),
                        colorScheme,
                      ),
                      label: 'المزيد',
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildIndexedStack(Delegate delegate) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        for (var index = 0; index < kHrShellTabCount; index++)
          index == 0 || _loadedTabs.contains(index)
              ? hrShellTab(
                  index: index,
                  delegate: delegate,
                  onNavigateToTab: _onTabSelected,
                )
              : const SizedBox.shrink(),
      ],
    );
  }
}
