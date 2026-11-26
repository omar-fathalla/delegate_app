import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/services/browser_history_stub.dart'
    if (dart.library.js_interop) 'package:delegate_app/core/services/browser_history_web.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/core/widgets/keyed_stream_builder.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/features/admin/presentation/pages/subscription_renewal_screen.dart';
import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:delegate_app/features/hr/presentation/hr_account_pages.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_photos_tab.dart';
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

  /// Web: the tab named by the URL (`/hr/<slug>`, TAS-139). The mounted
  /// shell follows it when it changes (browser back and forward). Null on
  /// mobile and outside the router: the shell then keeps its own tab state
  /// and never writes a URL.
  final int? routeTab;

  /// Web: inner pages the URL counts (`?inner=<n>`). A smaller count than
  /// the open inner pages closes the extra ones (browser back).
  final int routeInner;

  /// Web: address of the first inner page when it has one (TAS-190), for
  /// example `delegate/<id>` from `/hr/attendance/delegate/<id>`. The shell
  /// opens that page when it is not open yet (direct visit, reload,
  /// browser forward).
  final String? routeInnerUrl;

  const HRMainScreen({
    super.key,
    required this.delegate,
    this.initialIndex,
    this.routeTab,
    this.routeInner = 0,
    this.routeInnerUrl,
  });

  /// Test hook: replaces the tab bodies (they need a live Firestore).
  /// Always null in the app.
  @visibleForTesting
  static Widget Function(int index)? debugTabBuilder;

  /// Test hook: replaces [openHrDelegateAttendanceDetailById] when a URL
  /// opens the delegate detail page. Always null in the app.
  @visibleForTesting
  static Future<void> Function(
    BuildContext context, {
    required String delegateId,
    required Delegate hrDelegate,
    bool Function()? shouldOpen,
  })?
  debugOpenDelegateDetail;

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
  final GlobalKey<NavigatorState> _innerNavigator = GlobalKey<NavigatorState>(
    debugLabel: 'hr_inner_navigator',
  );

  /// Web: delegate filter for «سجل تعديلات الحضور», set when the detail
  /// attendance page opens the log for one delegate (TAS-146).
  HrAdjustmentsDelegateFilter? _adjustmentsFilter;

  /// Switches «الصور» to its permissions view when the retired
  /// «أذونات التصوير» slot is selected (TAS-149).
  final HrPhotosViewController _photosView = HrPhotosViewController();

  // Web URL sync (TAS-139). The shell writes `/hr/<slug>?inner=<n>` with
  // go_router; the router hands the URL back as [HRMainScreen.routeTab] and
  // [HRMainScreen.routeInner] on the same mounted shell.

  /// Inner pages ([pushHrInnerPage]) open over the current tab.
  int _innerDepth = 0;

  /// Address of the first open inner page, when it has one (TAS-190).
  String? _innerUrl;

  /// Inner-page address the shell is opening from the URL right now.
  String? _openingInnerUrl;

  /// Narrow web: inner pages pushed full screen on the root navigator,
  /// oldest first (TAS-189).
  final List<Route<dynamic>> _fullScreenInner = [];

  /// Narrow web: a context under the [HrInnerPageTracker], for pages the
  /// shell opens itself (settings, profile, a detail URL).
  final GlobalKey _scaffoldKey = GlobalKey(debugLabel: 'hr_shell_scaffold');

  /// True while the shell itself closes inner pages (tab switch, URL
  /// change). Those closes must not step the browser history back.
  bool _shellPopping = false;

  /// Layout of the last build: wide (sidebar + inner navigator) or narrow.
  bool? _lastWide;

  /// Real web: an in-app close of an inner page stepped the history back
  /// and the URL update has not arrived yet. A URL write in that window
  /// waits for it, so the late back step cannot undo a newer page.
  bool _awaitingHistoryBack = false;
  bool _syncAfterHistoryBack = false;
  Timer? _historyBackTimeout;
  bool _urlSyncScheduled = false;
  late final List<NavigatorObserver> _innerObservers = [
    _HrInnerUrlObserver(this),
  ];

  /// Only a web shell built by the router follows and writes the URL.
  bool get _urlSync => WebRuntimePolicy.isWeb && widget.routeTab != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialIndex ?? widget.routeTab ?? _homeIndex;
    if (initial == kHrTabPhotoPermissions) {
      _photosView.show(HrPhotosView.permissions);
    }
    _currentIndex = hrShellResolveTab(initial);
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
        openAdjustments: ({required delegateUID, required delegateName}) {
          if (!mounted) return;
          _onTabSelected(
            kHrTabAdjustments,
            adjustmentsFilter: HrAdjustmentsDelegateFilter(
              uid: delegateUID,
              name: delegateName,
            ),
          );
        },
      );
    }
    if (_urlSync && widget.routeInnerUrl != null) {
      // A direct visit or reload of `/hr/<tab>/delegate/<id>` (TAS-190):
      // open the page once the content area is built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyRoute();
      });
    }
  }

  @override
  void didUpdateWidget(HRMainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_urlSync) return;
    if (widget.routeTab == oldWidget.routeTab &&
        widget.routeInner == oldWidget.routeInner &&
        widget.routeInnerUrl == oldWidget.routeInnerUrl) {
      return;
    }
    // Navigator and setState work runs after this build.
    scheduleMicrotask(() {
      if (!mounted) return;
      if (_awaitingHistoryBack) {
        final resync = _syncAfterHistoryBack;
        _clearHistoryBack();
        if (resync) {
          // The shell moved on while the back step was in flight: write
          // its current page instead of following the older URL.
          _syncUrl();
          return;
        }
      }
      _applyRoute();
    });
  }

  /// Follows a URL change: switches to its tab and closes inner pages the
  /// URL no longer counts. Inner pages are never rebuilt from the URL,
  /// except a page with its own address (TAS-190), which is opened again.
  void _applyRoute() {
    if (!_urlSync) return;
    if (hrShellResolveTab(widget.routeTab!) != _currentIndex) {
      _onTabSelected(widget.routeTab!, syncUrl: false);
    }
    final url = widget.routeInnerUrl;
    if (url != null && _innerDepth > 0 && _innerUrl != url) {
      // Another addressed page is open: the URL names a different one.
      _closeInnerPages();
    }
    if (widget.routeInner < _innerDepth) {
      _closeInnerPages(keep: widget.routeInner);
    }
    if (url != null && _innerDepth == 0) _openRouteInnerPage(url);
  }

  /// Opens the inner page named by the URL ([HRMainScreen.routeInnerUrl]).
  Future<void> _openRouteInnerPage(String url) async {
    final delegateId = hrDelegateIdFromUrlPath(url);
    if (delegateId == null || _openingInnerUrl == url) return;
    final context = _innerPageContext;
    if (context == null) return;
    _openingInnerUrl = url;
    try {
      await (HRMainScreen.debugOpenDelegateDetail ??
          openHrDelegateAttendanceDetailById)(
        context,
        delegateId: delegateId,
        hrDelegate: widget.delegate,
        shouldOpen: () =>
            mounted &&
            _urlSync &&
            widget.routeInnerUrl == url &&
            _innerDepth == 0,
      );
    } finally {
      if (_openingInnerUrl == url) _openingInnerUrl = null;
    }
  }

  /// A context inside the content area, where [pushHrInnerPage] finds the
  /// inner navigator (wide web) or the tracker (narrow web).
  BuildContext? get _innerPageContext =>
      _innerNavigator.currentState?.context ?? _scaffoldKey.currentContext;

  /// Closes inner pages down to [keep]. Popups above them close too.
  void _closeInnerPages({int keep = 0}) {
    final nav = _innerNavigator.currentState;
    if (nav != null) {
      var close = _innerDepth - keep;
      _shellPopping = true;
      try {
        nav.popUntil((route) {
          if (route.isFirst) return true;
          if (keep > 0 && close <= 0) return true;
          if (isHrInnerRoute(route)) close--;
          return false;
        });
      } finally {
        _shellPopping = false;
      }
    }
    _closeFullScreenInnerPages(keep: keep);
  }

  /// Narrow web: pops the full-screen inner pages above the first [keep]
  /// ones, with anything opened over them (TAS-189).
  void _closeFullScreenInnerPages({int keep = 0}) {
    if (_fullScreenInner.length <= keep) return;
    final nav = _fullScreenInner.first.navigator;
    if (nav == null) return;
    final stopAt = keep > 0 ? _fullScreenInner[keep - 1] : null;
    final shellRoute = ModalRoute.of(context);
    _shellPopping = true;
    try {
      nav.popUntil(
        (route) =>
            route.isFirst ||
            (stopAt != null ? route == stopAt : route == shellRoute),
      );
    } finally {
      _shellPopping = false;
    }
  }

  /// Wide to narrow drops the inner navigator, and its pages go with it
  /// without a pop the observers hear. Forget them, so their address (a
  /// delegate id, TAS-190) does not stick to the next inner page, and write
  /// the URL of what is on screen now (TAS-199).
  void _onLayoutChanged(bool wide) {
    final was = _lastWide;
    _lastWide = wide;
    if (was != true || wide) return;
    final lost = _innerDepth - _fullScreenInner.length;
    if (lost <= 0) return;
    _innerDepth = _fullScreenInner.length;
    if (_innerDepth == 0) _innerUrl = null;
    _scheduleUrlSync();
  }

  void _fullScreenInnerOpened(Route<dynamic> route) {
    _fullScreenInner.add(route);
    _innerPageOpened(route);
  }

  void _fullScreenInnerClosed(Route<dynamic> route) {
    if (!_fullScreenInner.remove(route)) return;
    if (!mounted) return;
    _innerPageClosed(route);
  }

  void _innerPageOpened(Route<dynamic> route) {
    if (_innerDepth == 0) _innerUrl = hrInnerRouteUrl(route);
    _innerDepth++;
    _scheduleUrlSync();
  }

  void _innerPageClosed(Route<dynamic> route) {
    if (_innerDepth > 0) _innerDepth--;
    if (_innerDepth == 0) _innerUrl = null;
    if (!_urlSync || _shellPopping) return;
    // Closed inside the app (its back button, or the page popped itself).
    // Step the browser history back over the entry its opening added, so
    // history and screen stay in line.
    if (widget.routeInner > _innerDepth) _stepHistoryBack();
  }

  void _stepHistoryBack() {
    if (!kIsWeb) {
      // Tests that force the web policy have no browser history: write
      // the shorter URL instead.
      _scheduleUrlSync();
      return;
    }
    _awaitingHistoryBack = true;
    _historyBackTimeout?.cancel();
    _historyBackTimeout = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      final resync = _syncAfterHistoryBack;
      _clearHistoryBack();
      if (resync) _syncUrl();
    });
    browserHistoryBack();
  }

  void _clearHistoryBack() {
    _awaitingHistoryBack = false;
    _syncAfterHistoryBack = false;
    _historyBackTimeout?.cancel();
    _historyBackTimeout = null;
  }

  /// Writes the current page after the current event, once.
  void _scheduleUrlSync() {
    if (!_urlSync || _urlSyncScheduled) return;
    _urlSyncScheduled = true;
    scheduleMicrotask(() {
      _urlSyncScheduled = false;
      if (mounted) _syncUrl();
    });
  }

  /// `go` to `/hr/<slug>?inner=<n>` when it differs from the last URL the
  /// router gave the shell. A new URL is a new browser history entry.
  void _syncUrl() {
    if (!_urlSync) return;
    if (_awaitingHistoryBack) {
      _syncAfterHistoryBack = true;
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final location = hrShellLocation(
      _currentIndex,
      inner: _innerDepth,
      innerUrl: _innerUrl,
    );
    final current = hrShellLocation(
      widget.routeTab!,
      inner: widget.routeInner,
      innerUrl: widget.routeInnerUrl,
    );
    if (location == current) return;
    router.go(location, extra: widget.delegate);
  }

  @override
  void dispose() {
    _historyBackTimeout?.cancel();
    HrShellLink.detach(this);
    _headerBridge.dispose();
    _photosView.dispose();
    super.dispose();
  }

  void _refreshHome() {
    setState(() {});
    final reload = _headerBridge.reloadHome;
    if (reload != null) unawaited(reload());
    // The open page's own data, when it registered a reload (TAS-148).
    if (_currentIndex != _homeIndex) {
      final page = _headerBridge.pageReload(_currentIndex);
      if (page != null) unawaited(page());
    }
  }

  /// [syncUrl] is false when the URL itself chose the tab (TAS-139).
  void _onTabSelected(
    int index, {
    HrAdjustmentsDelegateFilter? adjustmentsFilter,
    bool syncUrl = true,
  }) {
    // A sidebar click leaves any inner page of the previous tab.
    _closeInnerPages();
    // TAS-149: the retired permissions page opens «الصور» on its
    // permissions view.
    if (index == kHrTabPhotoPermissions) {
      _photosView.show(HrPhotosView.permissions);
      index = hrShellResolveTab(index);
    }
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
      // Opening the log from the sidebar shows every delegate; the detail
      // attendance page passes its delegate (TAS-146).
      if (index == kHrTabAdjustments) _adjustmentsFilter = adjustmentsFilter;
    });
    if (syncUrl) _scheduleUrlSync();
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
    final companyUID = widget.delegate.companyUID;
    return KeyedStreamBuilder<QuerySnapshot>(
      streamKey: ('leave_requests', companyUID),
      create: () => FirebaseFirestore.instance
          .collection('leave_requests')
          .where('companyUID', isEqualTo: companyUID)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return icon;
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return icon;
        return Badge(
          label: Text(
            '$count',
            style: const TextStyle(
              fontSize: HrFont.labelSmall,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: colorScheme.error,
          textColor: colorScheme.onError,
          child: icon,
        );
      },
    );
  }

  /// Pending count of [collection] as plain trailing text for the narrow
  /// web menu (TAS-154). Shows nothing when the count is zero.
  Widget _buildPendingCountText(String collection, ColorScheme colorScheme) {
    if (widget.delegate.companyUID.isEmpty) return const SizedBox.shrink();
    final companyUID = widget.delegate.companyUID;
    // Created once per (collection, company); if Firebase isn't ready
    // (tests, or a build without a default app) the error shows nothing.
    return KeyedStreamBuilder<QuerySnapshot>(
      streamKey: (collection, companyUID),
      create: () => FirebaseFirestore.instance
          .collection(collection)
          .where('companyUID', isEqualTo: companyUID)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasError ? 0 : snapshot.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Text(
          '$count',
          style: TextStyle(
            fontSize: HrFont.body,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }

  /// شارة طلبات فك وربط الأجهزة المعلقة
  Widget _buildDeviceRequestsBadge(Widget icon, ColorScheme colorScheme) {
    if (widget.delegate.companyUID.isEmpty) return icon;
    final companyUID = widget.delegate.companyUID;
    return KeyedStreamBuilder<QuerySnapshot>(
      streamKey: ('device_unbind_requests', companyUID),
      create: () => FirebaseFirestore.instance
          .collection('device_unbind_requests')
          .where('companyUID', isEqualTo: companyUID)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return icon;
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return icon;
        return Badge(
          label: Text(
            '$count',
            style: const TextStyle(
              fontSize: HrFont.labelSmall,
              fontWeight: FontWeight.bold,
            ),
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
      case 'penalty_rules_catalog':
      case 'penalties_management':
        final tab = hrShellItemById(value)?.tabIndex;
        if (tab != null) _onTabSelected(tab);
        break;
      case kHrRetiredPhotoPermissionsId:
        _onTabSelected(kHrTabPhotoPermissions);
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
  /// (TAS-157). Narrow web opens it full screen through the tracker, so the
  /// browser back button closes it (TAS-189). Returns false on mobile; the
  /// caller then keeps the full-screen push.
  bool _openAccountPageInShell(void Function(BuildContext inner) open) {
    if (!WebRuntimePolicy.isWeb) return false;
    final inner = _innerPageContext;
    if (inner == null) return false;
    // One account page at a time, opened from the current tab.
    _closeInnerPages();
    open(inner);
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
    _onLayoutChanged(isWideScreen);
    final isArabic = localeProvider.isArabic;
    final web = WebRuntimePolicy.isWeb;
    final delegatesRail =
        web &&
        _currentIndex == kHrTabDelegates &&
        MediaQuery.sizeOf(context).width < _delegatesRailBelow;
    final menuItems = web
        ? const <PopupMenuEntry<String>>[]
        : _buildMenuItems(context, l10n, colorScheme);
    final shell = Directionality(
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
            key: _scaffoldKey,
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
                            // Pending counts sit beside the label, not on
                            // the icon (TAS-154), like the web sidebar.
                            trailingFor: (item) => item.badgeCollection == null
                                ? null
                                : _buildPendingCountText(
                                    item.badgeCollection!,
                                    colorScheme,
                                  ),
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
    // Web: inner pages pushed without the wide shell's inner navigator
    // (narrow windows) report to the shell, which counts them in the URL
    // (TAS-189). Mobile is unchanged.
    if (!web) return shell;
    return HrInnerPageTracker(
      onOpened: _fullScreenInnerOpened,
      onClosed: _fullScreenInnerClosed,
      child: shell,
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
          observers: _innerObservers,
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
              ? HRMainScreen.debugTabBuilder?.call(index) ??
                    hrShellTab(
                      index: index,
                      delegate: delegate,
                      onNavigateToTab: _onTabSelected,
                      adjustmentsFilter: _adjustmentsFilter,
                      photosView: _photosView,
                    )
              : const SizedBox.shrink(),
      ],
    );
  }
}

/// Counts inner pages on the shell's content navigator (TAS-139).
class _HrInnerUrlObserver extends NavigatorObserver {
  _HrInnerUrlObserver(this._shell);

  final _HRMainScreenState _shell;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (isHrInnerRoute(route)) _shell._innerPageOpened(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (isHrInnerRoute(route)) _shell._innerPageClosed(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (isHrInnerRoute(route)) _shell._innerPageClosed(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final wasInner = oldRoute != null && isHrInnerRoute(oldRoute);
    final isInner = newRoute != null && isHrInnerRoute(newRoute);
    if (wasInner && !isInner) _shell._innerPageClosed(oldRoute);
    if (isInner && !wasInner) _shell._innerPageOpened(newRoute);
  }
}
