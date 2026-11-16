// WEB-ONLY: Material 3 desktop shell for the supervisor (company admin) role.
// Used only when kIsWeb && width >= kAdminDesktopMinWidth (see
// AdminDesktopShellWeb.shouldUse). Mobile and narrow web keep AdminMainScreen.
// Composes the existing shared tab screens without modifying them.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/admin/presentation/pages/admin_main_screen.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/web/admin_desktop/admin_desktop_home_web.dart';
import 'package:delegate_app/web/admin_desktop/admin_desktop_list_detail_web.dart';
import 'package:delegate_app/web/admin_desktop/admin_desktop_attendance_web.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/supervisor_permissions_screen.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_penalties_list_page.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_device_unbind_requests_screen.dart';
import 'package:delegate_app/features/profile/presentation/pages/user_profile_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// M3 window-size breakpoints (dp).
const double kAdminDesktopMinWidth = 840;
const double kAdminDrawerMinWidth = 1200;
const double kAdminContentMaxWidth = 1200;

class AdminDesktopShellWeb extends StatefulWidget {
  final Delegate delegate;

  /// Test hook: replaces the four tab screens (home, delegates, attendance, requests).
  final List<Widget>? screensOverride;

  /// Test hook: replaces [adminPendingCountStream].
  final Stream<int> Function(String collection)? pendingCountOverride;

  /// Page restored from the URL (`/admin/home?p=<page>`): a tab key
  /// (home, delegates, attendance, requests), an extra value or 'settings'.
  final String? initialPage;

  /// Test hook: replaces the extra/settings page bodies.
  final Widget Function(String page)? extraBodyOverride;

  /// Test hook: replaces the full app layout opened by [kAllToolsKey].
  final WidgetBuilder? allToolsOverride;

  const AdminDesktopShellWeb({
    super.key,
    required this.delegate,
    this.screensOverride,
    this.pendingCountOverride,
    this.initialPage,
    this.extraBodyOverride,
    this.allToolsOverride,
  });

  /// Opens the full app layout (every mobile menu target) on top of the
  /// shell; not a shell page, so it is never written to the URL.
  static const kAllToolsKey = 'all_tools';

  /// Tab keys used in the `p` query parameter.
  static const tabKeys = ['home', 'delegates', 'attendance', 'requests'];

  /// Extra pages shown inside the shell's content area.
  static const extraKeys = [
    'tasks',
    'supervisor_photo_permissions',
    'penalties_management',
    'device_unbind_requests',
    'profile',
    'settings',
  ];

  /// `p` captured by the router while the splash restores the session after
  /// a reload (the splash navigates to `/admin/home` without the query).
  static String? pendingPage;

  /// Test hook: receives every URL the shell writes.
  @visibleForTesting
  static void Function(Uri uri)? debugOnSyncUrl;

  /// Home is plain /admin/home; other tabs and extras keep ?p=.
  static Uri urlFor(String page) => page == 'home'
      ? Uri(path: '/admin/home')
      : Uri(path: '/admin/home', queryParameters: {'p': page});

  static bool isKnownPage(String? p) =>
      p != null && (tabKeys.contains(p) || extraKeys.contains(p));

  /// Only company supervisors (admin role with a company) get the desktop
  /// shell. Every other role reaching /admin/home, and accounts without a
  /// companyUID, keep their existing layout on web.
  static bool shouldUse(BuildContext context, Delegate delegate) =>
      shouldUseFor(
        isWeb: kIsWeb,
        delegate: delegate,
        width: MediaQuery.sizeOf(context).width,
      );

  @visibleForTesting
  static bool shouldUseFor({
    required bool isWeb,
    required Delegate delegate,
    required double width,
  }) {
    if (!isWeb) return false;
    if (delegate.role != UserRole.admin) return false;
    if (delegate.companyUID.trim().isEmpty) return false;
    return width >= kAdminDesktopMinWidth;
  }

  @override
  State<AdminDesktopShellWeb> createState() => _AdminDesktopShellWebState();
}

class _Dest {
  final IconData icon;
  final String label;
  final String? badgeCollection;
  const _Dest(this.icon, this.label, [this.badgeCollection]);
}

/// Extra supervisor menu items (same targets as the mobile popup menu).
class _Extra {
  final String value;
  final IconData icon;
  final String label;
  final String? badgeCollection;
  const _Extra(this.value, this.icon, this.label, [this.badgeCollection]);
}

class _AdminDesktopShellWebState extends State<AdminDesktopShellWeb> {
  int _index = 0;

  /// Extra page shown in the content area instead of the tabs (null = tabs).
  String? _extra;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPage;
    if (AdminDesktopShellWeb.isKnownPage(p)) {
      final t = AdminDesktopShellWeb.tabKeys.indexOf(p!);
      if (t >= 0) {
        _index = t;
      } else {
        _extra = p;
      }
      // Reload / deep link: the splash lands on plain /admin/home, so put
      // ?p= back once the restored page is on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncUrl(p);
      });
    }
    final d = widget.delegate;
    _screens = widget.screensOverride ??
        [
          AdminDesktopHomeWeb(delegate: d),
          AdminDelegatesListDetailWeb(adminDelegate: d),
          AdminDesktopAttendanceWeb(hrDelegate: d),
          HRRequestsListDetailWeb(hrDelegate: d),
        ];
  }

  List<_Dest> _dests(AppLocalizations l10n, bool ar) => [
        _Dest(Symbols.home_rounded, l10n.home),
        _Dest(Symbols.group_rounded, l10n.companyDelegates),
        _Dest(Symbols.event_available_rounded, ar ? 'الحضور' : 'Attendance'),
        _Dest(Symbols.inbox_rounded, ar ? 'الطلبات' : 'Requests',
            'leave_requests'),
      ];

  /// Order follows the app menus: profile first, penalties last (directly
  /// above logout), settings always at the bottom.
  List<_Extra> _extras(bool ar) => [
        _Extra('profile', Symbols.person_rounded,
            ar ? 'الملف الشخصي' : 'Profile'),
        _Extra('tasks', Symbols.task_alt_rounded, ar ? 'المهام' : 'Tasks'),
        _Extra('supervisor_photo_permissions', Symbols.photo_library_rounded,
            ar ? 'أذونات التصوير' : 'Photo Permissions'),
        _Extra('device_unbind_requests', Symbols.phonelink_lock_rounded,
            ar ? 'طلبات فك وربط الأجهزة' : 'Device unbind requests',
            'device_unbind_requests'),
        _Extra(AdminDesktopShellWeb.kAllToolsKey, Symbols.apps_rounded,
            ar ? 'كل أدوات المشرف' : 'All supervisor tools'),
        _Extra('penalties_management', Symbols.gavel_rounded,
            ar ? 'سجل المخالفات والغرامات' : 'Penalties'),
      ];


  /// Shows an extra page inside the shell (drawer stays visible) and keeps it
  /// in the URL so a reload restores it. Mobile keeps
  /// [AdminMainScreen.openSupervisorMenuTarget] (push).
  void _openExtra(String value) {
    if (value == AdminDesktopShellWeb.kAllToolsKey) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: widget.allToolsOverride ??
              (_) => AdminMainScreen(delegate: widget.delegate),
        ),
      );
      return;
    }
    setState(() => _extra = value);
    _syncUrl(value);
  }

  void _selectTab(int i) {
    setState(() {
      _index = i;
      _extra = null;
    });
    _syncUrl(AdminDesktopShellWeb.tabKeys[i]);
  }

  void _syncUrl(String page) {
    final uri = AdminDesktopShellWeb.urlFor(page);
    AdminDesktopShellWeb.debugOnSyncUrl?.call(uri);
    if (!kIsWeb) return;
    SystemNavigator.routeInformationUpdated(uri: uri, replace: true);
  }

  String _extraTitle(String page, AppLocalizations l10n, bool ar) {
    if (page == 'settings') return l10n.settings;
    for (final e in _extras(ar)) {
      if (e.value == page) return e.label;
    }
    return page;
  }

  Widget _extraBody(String page) {
    final o = widget.extraBodyOverride;
    if (o != null) return o(page);
    final d = widget.delegate;
    switch (page) {
      case 'tasks':
        return AdminTasksScreen(adminDelegate: d);
      case 'supervisor_photo_permissions':
        return MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => di.sl<PhotoPermissionBloc>()),
            BlocProvider(create: (_) => di.sl<BranchBloc>()),
          ],
          child: SupervisorPermissionsScreen(
              supervisorDelegate: d, showAppBar: false),
        );
      case 'penalties_management':
        return BlocProvider(
          create: (_) => di.sl<PenaltyBloc>(),
          child: AdminPenaltiesListPage(adminDelegate: d),
        );
      case 'device_unbind_requests':
        return HRDeviceUnbindRequestsScreen(hrDelegate: d, showAppBar: false);
      case 'profile':
        return UserProfileScreen(delegate: d);
      case 'settings':
        return SettingsScreen(delegate: d, showAppBar: false);
    }
    return const SizedBox.shrink();
  }

  Stream<int> _pending(String collection) =>
      widget.pendingCountOverride?.call(collection) ??
      adminPendingCountStream(widget.delegate, collection);

  final Map<String, Stream<int>> _streams = {};

  Widget _badged(Widget icon, String? collection) {
    if (collection == null) return icon;
    final stream =
        _streams.putIfAbsent(collection, () => _pending(collection).asBroadcastStream());
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          child: icon,
        );
      },
    );
  }

  Widget _notificationsButton(AppLocalizations l10n) {
    final d = widget.delegate;
    Widget button(int unread) => Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: IconButton(
            tooltip: l10n.notifications,
            icon: const Icon(Symbols.notifications_rounded),
            onPressed: () => context.push('/notifications', extra: d),
          ),
        );
    if (!di.sl.isRegistered<NotificationBloc>()) return button(0);
    return BlocProvider(
      create: (_) => di.sl<NotificationBloc>()
        ..add(SubscribeToUnreadCount(
          delegateUid: d.uid,
          organizationId: d.organizationUID,
          phoneNumber: d.phoneNumber,
          userRole: d.role.name,
          accountCreatedAt: d.createdAt,
        )),
      child: BlocBuilder<NotificationBloc, NotificationState>(
        builder: (context, state) =>
            button(state is NotificationLoaded ? state.unreadCount : 0),
      ),
    );
  }

  void _openSettings() => _openExtra('settings');

  bool _isAr(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';

  void _logout() => AppLogoutModal.show(context, delegate: widget.delegate);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final dests = _dests(l10n, ar);
    final useDrawer = width >= kAdminDrawerMinWidth;

    // Rail/drawer is first in the Row => start side (right in RTL).
    final nav = useDrawer
        ? _buildDrawer(context, dests, l10n)
        : _buildRail(context, dests, l10n);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        children: [
          nav,
          if (_isDark(context))
            VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(
                    context,
                    _extra != null
                        ? _extraTitle(_extra!, l10n, ar)
                        : dests[_index].label),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: kAdminContentMaxWidth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Material(
                            color: cs.surfaceContainerLow,
                            child: ScrollConfiguration(
                              behavior: const _DesktopScrollBehavior(),
                              child: Stack(children: [
                                // Tabs stay alive underneath the extra page.
                                Offstage(
                                  offstage: _extra != null,
                                  child: IndexedStack(
                                    index: _index,
                                    children: _screens,
                                  ),
                                ),
                                if (_extra != null)
                                  KeyedSubtree(
                                    key: ValueKey('extra_$_extra'),
                                    child: _extraBody(_extra!),
                                  ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Dark: nav matches the page (surface) and a divider separates it.
  /// Light keeps surfaceContainer.
  static bool _isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  Color _navColor(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return _isDark(c) ? cs.surface : cs.surfaceContainer;
  }

  Widget _buildTopBar(BuildContext context, String pageTitle) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = widget.delegate;
    final name = d.fullName.isNotEmpty ? d.fullName : d.firstName;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kAdminContentMaxWidth - 48),
        child: Row(
          children: [
            Expanded(
              child: Text(pageTitle,
                  style: tt.headlineSmall?.copyWith(color: cs.onSurface)),
            ),
            _notificationsButton(AppLocalizations.of(context)!),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: tt.titleSmall?.copyWith(color: cs.onSurface)),
                Text(
                  [ar ? 'مشرف' : 'Supervisor', if (d.companyName.isNotEmpty) d.companyName]
                      .join(' · '),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              child: Text(name.isNotEmpty ? name.characters.first : '?'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRail(
      BuildContext context, List<_Dest> dests, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 80,
      child: NavigationRail(
        backgroundColor: _navColor(context),
        indicatorColor: cs.secondaryContainer,
        labelType: NavigationRailLabelType.all,
        selectedIndex: _extra == null ? _index : null,
        groupAlignment: -1,
        onDestinationSelected: _selectTab,
        destinations: [
          for (final d in dests)
            NavigationRailDestination(
              icon: _badged(Icon(d.icon, fill: 0), d.badgeCollection),
              selectedIcon: _badged(Icon(d.icon, fill: 1), d.badgeCollection),
              label: Text(d.label, textAlign: TextAlign.center),
            ),
        ],
        trailing: Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                MenuAnchor(
                  menuChildren: [
                    for (final e in _extras(_isAr(context)))
                      MenuItemButton(
                        leadingIcon: _badged(Icon(e.icon), e.badgeCollection),
                        onPressed: () => _openExtra(e.value),
                        child: Text(e.label),
                      ),
                  ],
                  builder: (context, controller, _) => IconButton(
                    key: const ValueKey('rail_more'),
                    tooltip: _isAr(context) ? 'المزيد' : 'More',
                    icon: _badged(const Icon(Symbols.more_horiz_rounded),
                        'device_unbind_requests'),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                ),
                IconButton(
                  tooltip: l10n.logout,
                  icon: const Icon(Symbols.logout_rounded),
                  onPressed: _logout,
                ),
                IconButton(
                  tooltip: l10n.settings,
                  icon: const Icon(Symbols.settings_rounded),
                  onPressed: _openSettings,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  int? _drawerSelected(int tabCount) {
    final e = _extra;
    if (e == null) return _index;
    // Destinations: tabs, extras, logout, settings (last).
    if (e == 'settings') return tabCount + _extras(true).length + 1;
    final i = _extras(true).indexWhere((x) => x.value == e);
    return i < 0 ? null : tabCount + i;
  }

  Widget _buildDrawer(
      BuildContext context, List<_Dest> dests, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 300, // standard drawer, <= 360
      child: NavigationDrawer(
        backgroundColor: _navColor(context),
        indicatorColor: cs.secondaryContainer,
        elevation: 0,
        selectedIndex: _drawerSelected(dests.length),
        onDestinationSelected: (i) {
          final extras = _extras(_isAr(context));
          if (i < dests.length) {
            _selectTab(i);
          } else if (i < dests.length + extras.length) {
            _openExtra(extras[i - dests.length].value);
          } else if (i == dests.length + extras.length) {
            _logout();
          } else {
            _openSettings();
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
            child: Text('Tashil',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: cs.primary)),
          ),
          for (final d in dests)
            NavigationDrawerDestination(
              icon: _badged(Icon(d.icon, fill: 0), d.badgeCollection),
              selectedIcon: _badged(Icon(d.icon, fill: 1), d.badgeCollection),
              label: Text(d.label),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            child: Divider(),
          ),
          for (final e in _extras(_isAr(context)))
            NavigationDrawerDestination(
              icon: _badged(Icon(e.icon), e.badgeCollection),
              label: Text(e.label),
            ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.logout_rounded),
            label: Text(l10n.logout),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            child: Divider(),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.settings_rounded),
            label: Text(l10n.settings),
          ),
        ],
      ),
    );
  }
}

class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();
  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      Scrollbar(controller: details.controller, child: child);
}

/// Pending-count badge source for the shell; same scoping as the mobile
/// admin menu badges (organization admins by organization, everyone else by
/// company, nothing without a scope).
Stream<int> adminPendingCountStream(Delegate delegate, String collection) {
  Query<Map<String, dynamic>> query = FirebaseFirestore.instance
      .collection(collection)
      .where('status', isEqualTo: 'pending');
  if (delegate.role == UserRole.organizationAdmin) {
    if (delegate.organizationUID.isEmpty) return Stream<int>.value(0);
    query = query.where('organizationUID', isEqualTo: delegate.organizationUID);
    if (delegate.companyUID.isNotEmpty) {
      query = query.where('companyUID', isEqualTo: delegate.companyUID);
    }
  } else if (delegate.companyUID.isNotEmpty) {
    query = query.where('companyUID', isEqualTo: delegate.companyUID);
  } else {
    return Stream<int>.value(0);
  }
  final companyUID = delegate.companyUID;
  return query.snapshots().map((s) => companyUID.isEmpty
      ? s.docs.length
      : s.docs.where((d) => d.data()['companyUID'] == companyUID).length);
}
