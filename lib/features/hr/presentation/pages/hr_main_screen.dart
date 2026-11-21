import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/features/admin/presentation/pages/subscription_renewal_screen.dart';
import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:delegate_app/features/hr/presentation/hr_account_pages.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_top_bar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_more_bottom_sheet.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_web_overflow_menu.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/hr_web_account_button.dart';
import 'package:delegate_app/web/hr_system/hr_shell_link.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

class HRMainScreen extends StatefulWidget {
  final Delegate delegate;

  /// Defaults to [hrShellHomeTab]: the overview on web, attendance on mobile.
  final int? initialIndex;

  const HRMainScreen({super.key, required this.delegate, this.initialIndex});

  @override
  State<HRMainScreen> createState() => _HRMainScreenState();
}

class _HRMainScreenState extends State<HRMainScreen> {
  late int _currentIndex;
  late final Set<int> _loadedTabs;
  bool _isSidebarExpanded = true;

  /// Web «مناديب الشركة» (MD3 Model 1): below this width the side nav is the
  /// rail while that tab is open, unless the user expands it.
  static const double _delegatesRailBelow = 1200;
  bool? _delegatesNavExpandedOverride;
  final int _homeIndex = hrShellHomeTab(isWeb: WebRuntimePolicy.isWeb);
  final HrWebHeaderBridge _headerBridge = HrWebHeaderBridge();

  /// Web, wide windows: inner pages open in this navigator so the sidebar
  /// and the top bar stay (TAS-136).
  final GlobalKey<NavigatorState> _innerNavigator =
      GlobalKey<NavigatorState>(debugLabel: 'hr_inner_navigator');

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? _homeIndex;
    _loadedTabs = {_currentIndex};
    if (WebRuntimePolicy.isWeb) {
      HrShellLink.attach(
        owner: this,
        selectTab: (index) {
          if (mounted) _onTabSelected(index);
        },
        selectMenu: (id) {
          if (mounted) _onMenuSelected(id);
        },
        bridge: _headerBridge,
      );
    }
  }

  @override
  void dispose() {
    HrShellLink.detach(this);
    _headerBridge.dispose();
    super.dispose();
  }

  void _refreshHome() {
    setState(() {});
    final reload = _headerBridge.reloadHome;
    if (reload != null) unawaited(reload());
  }

  void _onTabSelected(int index) {
    // A sidebar click leaves any inner page of the previous tab.
    _innerNavigator.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

  /// تحويل مؤشر التبويب النشط إلى موقعه في الشريط السفلي للموبايل (4 أساسية + المزيد)
  int _getBottomNavIndex(int currentTabIndex) {
    if (WebRuntimePolicy.isWeb) {
      final slot = hrBottomNavTabs(isWeb: true).indexOf(currentTabIndex);
      return slot < 0 ? 4 : slot;
    }
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
    if (WebRuntimePolicy.isWeb && bottomNavIndex < 4) {
      _onTabSelected(hrBottomNavTabs(isWeb: true)[bottomNavIndex]);
      return;
    }
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
            style: const TextStyle(fontSize: HrFont.labelSmall, fontWeight: FontWeight.bold),
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
            style: const TextStyle(fontSize: HrFont.labelSmall, fontWeight: FontWeight.bold),
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
        if (_openAccountPageInShell(
          (inner) => HrAccountPages.openProfile(inner, delegate),
        )) {
          break;
        }
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
      case 'overview':
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
        if (_openAccountPageInShell(
          (inner) => HrAccountPages.openSettings(inner, delegate),
        )) {
          break;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                SettingsScreen(delegate: delegate, showAppBar: true),
          ),
        );
        break;
    }
  }

  /// Wide web: opens an account page (settings, profile) inside the content
  /// area, on top of the shell tabs, so the sidebar and the top bar stay
  /// (TAS-157). Returns false when there is no inner navigator (mobile,
  /// narrow web); the caller then keeps the full-screen push.
  bool _openAccountPageInShell(void Function(BuildContext inner) open) {
    if (!WebRuntimePolicy.isWeb) return false;
    final nav = _innerNavigator.currentState;
    if (nav == null) return false;
    // One account page at a time, opened from the current tab.
    nav.popUntil((route) => route.isFirst);
    open(nav.context);
    return true;
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
                  fontSize: HrFont.body,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
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
    final web = WebRuntimePolicy.isWeb;
    final delegatesRail = web &&
        _currentIndex == kHrTabDelegates &&
        MediaQuery.sizeOf(context).width < _delegatesRailBelow;
    final menuItems = web
        ? const <PopupMenuEntry<String>>[]
        : _buildMenuItems(context, l10n, colorScheme);
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: HrWebHeaderBridgeScope(
        bridge: _headerBridge,
        child: PopScope(
          canPop: isWideScreen || _currentIndex == _homeIndex,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_currentIndex != _homeIndex) {
              _onTabSelected(_homeIndex);
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
                    extraActions: web ? _narrowWebHeaderActions() : null,
                    menuButton: web
                        ? HrWebOverflowMenu(
                            delegate: delegate,
                            currentIndex: _currentIndex,
                            onSelected: _onMenuSelected,
                            wrapIcon: (item, icon) {
                              if (item.badgeCollection == 'leave_requests') {
                                return _buildLeaveRequestsBadge(
                                  icon,
                                  colorScheme,
                                );
                              }
                              if (item.badgeCollection ==
                                  'device_unbind_requests') {
                                return _buildDeviceRequestsBadge(
                                  icon,
                                  colorScheme,
                                );
                              }
                              return icon;
                            },
                          )
                        : null,
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
                        isExpanded: delegatesRail
                            ? (_delegatesNavExpandedOverride ?? false)
                            : _isSidebarExpanded,
                        onToggleExpanded: () {
                          setState(() {
                            if (delegatesRail) {
                              _delegatesNavExpandedOverride =
                                  !(_delegatesNavExpandedOverride ?? false);
                            } else {
                              _isSidebarExpanded = !_isSidebarExpanded;
                            }
                          });
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
                              onRefresh: _refreshHome,
                              onMenuSelected: _onMenuSelected,
                              menuItems: menuItems,
                              webBell: web
                                  ? ListenableBuilder(
                                      listenable: _headerBridge,
                                      builder: (context, _) => HrWebHeaderBell(
                                        unread: _headerBridge.unread,
                                        onPressed:
                                            _headerBridge.openNotifications,
                                      ),
                                    )
                                  : null,
                              webAccount: web
                                  ? (showName) => HrWebAccountButton(
                                      delegate: delegate,
                                      showName: showName,
                                      onOpenProfile: () =>
                                          _onMenuSelected('profile'),
                                    )
                                  : null,
                            ),
                            Expanded(
                              child: web
                                  ? _buildInnerNavigator(delegate)
                                  : _buildIndexedStack(delegate),
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
                    selectedIndex: _getBottomNavIndex(_currentIndex),
                    onDestinationSelected: _onBottomNavSelected,
                    destinations: [
                      if (WebRuntimePolicy.isWeb)
                        const NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home_rounded),
                          label: 'الرئيسية',
                        )
                      else
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
      ),
    );
  }

  List<Widget> _narrowWebHeaderActions() => [
    ListenableBuilder(
      listenable: _headerBridge,
      builder: (context, _) => HrWebHeaderBell(
        unread: _headerBridge.unread,
        onPressed: _headerBridge.openNotifications,
        toolbar: false,
      ),
    ),
    IconButton(
      key: const ValueKey('hr_web_header_refresh'),
      tooltip: 'تحديث البيانات',
      onPressed: _refreshHome,
      icon: const Icon(Icons.refresh_rounded),
    ),
  ];

  /// The content area of the wide web shell. Tabs are the first page; inner
  /// pages from [pushHrInnerPage] go on top, inside the content area.
  Widget _buildInnerNavigator(Delegate delegate) {
    return NavigatorPopHandler(
      onPopWithResult: (_) => _innerNavigator.currentState?.maybePop(),
      child: HrInnerPageHost(
        navigatorKey: _innerNavigator,
        parentTitle: hrShellPageLabel(_currentIndex, isWeb: true),
        child: Navigator(
          key: _innerNavigator,
          pages: [
            MaterialPage<void>(
              key: const ValueKey('hr_shell_tabs'),
              child: _buildIndexedStack(delegate),
            ),
          ],
          onDidRemovePage: (_) {},
        ),
      ),
    );
  }

  Widget _buildIndexedStack(Delegate delegate) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        for (var index = 0; index < kHrShellTabCount; index++)
          index == _homeIndex || _loadedTabs.contains(index)
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
