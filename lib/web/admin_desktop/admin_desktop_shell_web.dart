// WEB-ONLY: Material 3 desktop shell for the supervisor (company admin) role.
// Used only when kIsWeb && width >= kAdminDesktopMinWidth (see
// AdminDesktopShellWeb.shouldUse). Mobile and narrow web keep AdminMainScreen.
// Composes the existing shared tab screens without modifying them.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
import 'package:delegate_app/l10n/app_localizations.dart';

/// M3 window-size breakpoints (dp).
const double kAdminDesktopMinWidth = 840;
const double kAdminDrawerMinWidth = 1200;
const double kAdminContentMaxWidth = 1200;

class AdminDesktopShellWeb extends StatefulWidget {
  final Delegate delegate;

  /// Test hook: replaces the four tab screens (home, delegates, attendance, requests).
  final List<Widget>? screensOverride;

  /// Test hook: replaces [AdminMainScreen.pendingCountStream].
  final Stream<int> Function(String collection)? pendingCountOverride;

  const AdminDesktopShellWeb({
    super.key,
    required this.delegate,
    this.screensOverride,
    this.pendingCountOverride,
  });

  /// Only plain supervisors get the desktop shell; other admin roles keep
  /// their existing layout.
  static bool shouldUse(BuildContext context, Delegate delegate) {
    if (!kIsWeb) return false;
    const otherRoles = {
      UserRole.superAdmin,
      UserRole.technicalSupport,
      UserRole.organizationAdmin,
      UserRole.branchesMarketingManager,
    };
    if (otherRoles.contains(delegate.role)) return false;
    return MediaQuery.sizeOf(context).width >= kAdminDesktopMinWidth;
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
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
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

  List<_Extra> _extras(bool ar) => [
        _Extra('tasks', Symbols.task_alt_rounded, ar ? 'المهام' : 'Tasks'),
        _Extra('supervisor_photo_permissions', Symbols.photo_library_rounded,
            ar ? 'أذونات التصوير' : 'Photo Permissions'),
        _Extra('penalties_management', Symbols.gavel_rounded,
            ar ? 'نظام الغرامات والمخالفات' : 'Penalties'),
        _Extra('device_unbind_requests', Symbols.phonelink_lock_rounded,
            ar ? 'طلبات فك ربط الأجهزة' : 'Device unbind requests',
            'device_unbind_requests'),
        _Extra('profile', Symbols.person_rounded,
            ar ? 'الملف الشخصي' : 'Profile'),
      ];

  void _openExtra(String value) =>
      AdminMainScreen.openSupervisorMenuTarget(context, widget.delegate, value);

  Stream<int> _pending(String collection) =>
      widget.pendingCountOverride?.call(collection) ??
      AdminMainScreen.pendingCountStream(widget.delegate, collection);

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

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            SettingsScreen(delegate: widget.delegate, showAppBar: true),
      ));

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
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, dests[_index].label),
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
                              child: IndexedStack(
                                index: _index,
                                children: _screens,
                              ),
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
        backgroundColor: cs.surfaceContainer,
        indicatorColor: cs.secondaryContainer,
        labelType: NavigationRailLabelType.all,
        selectedIndex: _index,
        groupAlignment: -1,
        onDestinationSelected: (i) => setState(() => _index = i),
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
                  tooltip: l10n.settings,
                  icon: const Icon(Symbols.settings_rounded),
                  onPressed: _openSettings,
                ),
                IconButton(
                  tooltip: l10n.logout,
                  icon: const Icon(Symbols.logout_rounded),
                  onPressed: _logout,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(
      BuildContext context, List<_Dest> dests, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 300, // standard drawer, <= 360
      child: NavigationDrawer(
        backgroundColor: cs.surfaceContainer,
        indicatorColor: cs.secondaryContainer,
        elevation: 0,
        selectedIndex: _index < dests.length ? _index : null,
        onDestinationSelected: (i) {
          final extras = _extras(_isAr(context));
          if (i < dests.length) {
            setState(() => _index = i);
          } else if (i < dests.length + extras.length) {
            _openExtra(extras[i - dests.length].value);
          } else if (i == dests.length + extras.length) {
            _openSettings();
          } else {
            _logout();
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            child: Divider(),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.settings_rounded),
            label: Text(l10n.settings),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Symbols.logout_rounded),
            label: Text(l10n.logout),
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
