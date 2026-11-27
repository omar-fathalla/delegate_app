import 'package:delegate_app/core/widgets/offline_banner.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/home/presentation/pages/delegate_home_screen.dart';
import 'package:delegate_app/features/home/presentation/chain_auto_switch_session.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/photo_reports_refresh.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/auth/domain/role_home.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_delegate.dart';
import 'package:delegate_app/features/tasks/presentation/pages/delegate_tasks_screen.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/features/penalties/presentation/pages/penalty_rules_catalog_page.dart';
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'dart:async';
import 'package:delegate_app/features/admin/presentation/pages/manage_organizations_page.dart';
import 'package:delegate_app/features/hr/presentation/pages/delegate_leaves_and_requests_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/design/widgets/navigation.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The copy of [current] in [latest] whose organization or company name
/// differs from the cached one, or null when nothing changed.
Delegate? freshProfileFor(Delegate current, List<Delegate> latest) {
  for (final d in latest) {
    if (d.uid != current.uid ||
        d.organizationUID != current.organizationUID ||
        d.companyUID != current.companyUID) {
      continue;
    }
    final org = d.organizationName.trim();
    final co = d.companyName.trim();
    if ((org.isNotEmpty && org != current.organizationName.trim()) ||
        (co.isNotEmpty && co != current.companyName.trim())) {
      return d;
    }
    return null;
  }
  return null;
}


class MainScreen extends StatefulWidget {
  final Delegate delegate;

  const MainScreen({super.key, required this.delegate});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  /// Scroll direction for the hiding navigation bar (TAS-350).
  final _bar = HideOnScroll();

  /// Tracks which tabs have been visited so we only build them once.
  final Set<int> _initializedTabs = {0}; // Tab 0 (Attendance) loads first

  List<Delegate> _allDelegates = [];

  /// Paused after an undo or a manual chain pick, for this login (TAS-245).
  bool get _autoSwitchPaused =>
      ChainAutoSwitchSession.isPaused(widget.delegate.uid);

  @override
  void initState() {
    super.initState();
    // An automatic chain switch rebuilds MainScreen (keyed by org): reopen
    // the tab the delegate was on (TAS-245).
    final tab = ChainAutoSwitchSession.takePendingTab();
    if (tab != null) {
      _currentIndex = tab;
      _initializedTabs.add(tab);
    }
    _loadAllDelegates();
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate.organizationUID != widget.delegate.organizationUID ||
        oldWidget.delegate.companyUID != widget.delegate.companyUID ||
        oldWidget.delegate.uid != widget.delegate.uid) {
      final keep = ChainAutoSwitchSession.takePendingTab();
      setState(() {
        _fresh = null;
        _currentIndex = keep ?? 0;
        _initializedTabs.clear();
        _initializedTabs.add(0);
        if (keep != null) _initializedTabs.add(keep);
      });
      _loadAllDelegates();
    }
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  List<Delegate> _filterDelegatesForContext(List<Delegate> delegates) {
    if (widget.delegate.role == UserRole.delegate) {
      // In mobile delegate workspace, only show field delegate/promoter chains
      final fieldProfiles = delegates.where((d) => d.role == UserRole.delegate).toList();
      return fieldProfiles.isNotEmpty ? fieldProfiles : delegates;
    }
    return delegates;
  }

  Future<void> _loadAllDelegates() async {
    final result = await di.sl<AuthRepository>().getCachedAllDelegates();
    result.fold((_) {}, (delegates) {
      if (mounted) setState(() => _allDelegates = _filterDelegatesForContext(delegates));
    });

    // Stale-While-Revalidate: fetch latest delegates from remote to sync new chains/organizations
    if (widget.delegate.phoneNumber.isNotEmpty) {
      // TAS-272: a delegate refreshes its own copies in every chain; the
      // staff lookup returned nothing for delegates, so new chains never
      // showed up until a re-login.
      final repo = di.sl<AuthRepository>();
      final remoteResult = widget.delegate.role == UserRole.delegate
          ? await repo.refreshDelegateProfiles(widget.delegate.phoneNumber)
          : await repo.getDelegatesByPhone(widget.delegate.phoneNumber);
      remoteResult.fold((_) {}, (latestDelegates) {
        if (latestDelegates.isNotEmpty) {
          di.sl<AuthRepository>().cacheAllDelegates(latestDelegates);
          _adoptFreshNames(latestDelegates);
          if (mounted) {
            setState(() => _allDelegates = _filterDelegatesForContext(latestDelegates));
          }
        }
      });
    }
  }

  /// The server copy of the profile in use, when its organization or company
  /// name changed since the cached one (TAS-384). The header and the home
  /// card read these names; without this they stayed as they were at sign in
  /// (empty, or an old name) until the next login.
  Delegate? _fresh;

  void _adoptFreshNames(List<Delegate> latest) {
    final current = widget.delegate;
    final match = freshProfileFor(current, latest);
    if (match == null || !mounted) return;
    setState(() => _fresh = match);
    di.sl<CacheDelegate>()(match);
  }

  void _showLogoutDialog(BuildContext context) {
    AppLogoutModal.show(context, delegate: widget.delegate);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = _fresh ?? widget.delegate;
    final colorScheme = Theme.of(context).colorScheme;

    void onMenu(String value) {
          if (value == 'profile') {
            context.push('/user-profile', extra: delegate);
          } else if (value == 'penalties') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider(
                  create: (_) => di.sl<PenaltyBloc>()
                    ..add(LoadDelegatePenaltiesEvent(delegate)),
                  child: CompanyPenaltiesSettingsPage(
                    delegate: delegate,
                    showAppBar: true,
                  ),
                ),
              ),
            );
          } else if (value == 'penalty_rules_catalog') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PenaltyRulesCatalogPage(
                  currentDelegate: delegate,
                ),
              ),
            );
          } else if (value == 'delegate_subscriptions') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DelegateSubscriptionRequestsPage(
                  currentAdmin: delegate,
                ),
              ),
            );
          } else if (value == 'manage_organizations') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ManageOrganizationsPage(),
              ),
            );
          } else if (value == 'org_switch') {
            _showOrgSwitcher(context, colorScheme);
          } else if (value == 'tasks') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider(
                  create: (context) => di.sl<DelegateTasksBloc>(),
                  child: DelegateTasksScreen(delegate: delegate),
                ),
              ),
            );
          } else if (value == 'leaves_and_requests') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DelegateLeavesAndRequestsScreen(
                  delegate: delegate,
                ),
              ),
            );
          } else if (value == 'logout') {
            _showLogoutDialog(context);
          } else if (value == 'settings') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  delegate: delegate,
                  showAppBar: true,
                ),
              ),
            );
          }
        }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: UniversalAppHeader(
        delegate: delegate,
        extraActions: [
          // Notification Bell with Badge
          BlocProvider(
            create: (_) => di.sl<NotificationBloc>()
              ..add(
                SubscribeToUnreadCount(
                  delegateUid: delegate.uid,
                  organizationId: delegate.organizationUID,
                  phoneNumber: delegate.phoneNumber,
                  userRole: delegate.role.name,
                  accountCreatedAt: delegate.createdAt,
                ),
              ),
            child: BlocBuilder<NotificationBloc, NotificationState>(
              builder: (context, state) {
                final unreadCount = state is NotificationLoaded
                    ? state.unreadCount
                    : 0;

                // M3: the badge sits on the icon, not on the 48dp button
                // corner (it was far from the bell, and under the DEV ribbon).
                return IconButton(
                    key: const Key('header_notifications_button'),
                    icon: Badge(
                      key: const Key('header_notifications_badge'),
                      label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                      isLabelVisible: unreadCount > 0,
                      child: const Icon(Symbols.notifications_rounded),
                    ),
                    tooltip: l10n.notifications,
                    onPressed: () {
                      context.push('/notifications', extra: delegate);
                    },
                );
              },
            ),
          ),
        ],
        useDrawer: true,
        onMenuSelected: onMenu,
        menuItems: const [],
      ),
      drawer: _buildDrawer(context, delegate, l10n, onMenu),
          body: _bar.listener(
            child: Column(
              children: [
                OfflineBanner(onRetry: () => setState(() {})),
                Expanded(child: _buildBody(delegate)),
              ],
            ),
          ),
          // TAS-350 (C-17): M3 navigation bar that hides while the content
          // scrolls down and comes back on scroll up (never with a screen
          // reader on).
          bottomNavigationBar: HidingNavigationBar(
            visible: _bar,
            destinations: _tabs(l10n),
            selectedIndex: _currentIndex,
            onDestinationSelected: _selectTab,
          ),
        );
  }

  /// Lazy-builds tabs: only creates a tab widget when it's first visited,
  /// then keeps it alive via M3FadeThroughIndexedStack with smooth M3 transition.
  Widget _buildBody(Delegate delegate) {
    return M3FadeThroughIndexedStack(
      index: _currentIndex,
      children: [
        // Tab 0: Home (always initialized)
        DelegateHomeScreen(
          delegate: delegate,
          onNavigateToAttendance: () {
            setState(() {
              _currentIndex = 1;
              _initializedTabs.add(1);
            });
          },
        ),

        // Tab 1: Attendance
        if (_initializedTabs.contains(1))
          AttendanceScreen(
            delegate: delegate,
            memberships: _allDelegates,
            onAutoSwitchChain: _autoSwitchPaused ? null : _autoSwitchToChain,
          )
        else
          const SizedBox.shrink(),

        // Tab 2: Leaves & Requests (طلباتي)
        if (_initializedTabs.contains(2))
          DelegateLeavesAndRequestsScreen(
            delegate: delegate,
            showAppBar: false,
          )
        else
          const SizedBox.shrink(),

        // Tab 3: Photo Reports
        if (_initializedTabs.contains(3))
          BlocProvider(
            create: (context) => di.sl<PhotoPermissionBloc>(),
            child: MonthlyPhotoReportScreen(
              delegate: delegate,
              // Single title: the workspace app bar; refresh = pull-to-refresh.
              showAppBar: false,
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  /// Switches chain because the delegate is standing in a branch of
  /// [target]'s chain (TAS-245). Stays on the attendance tab and offers
  /// an undo that also pauses auto switching for this session.
  Future<void> _autoSwitchToChain(Delegate target, String branchLabel) async {
    final previous = widget.delegate;
    if (target.organizationUID == previous.organizationUID &&
        target.companyUID == previous.companyUID) {
      return;
    }
    final cacheDelegate = di.sl<CacheDelegate>();
    await cacheDelegate(target);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final l10n = AppLocalizations.of(context)!;
    final chainLabel = target.companyName.isNotEmpty
        ? '${target.organizationName} - ${target.companyName}'
        : target.organizationName;
    ChainAutoSwitchSession.openTabAfterSwitch(1);
    context.go(homePathForRole(target.role), extra: target);
    // A MaterialBanner, not a SnackBar: the attendance tab shows sync
    // SnackBars right after the switch and AppSnackBar hides the current
    // one, which took the undo away (seen on the M31).
    Timer? autoHide;
    void hideBanner() {
      autoHide?.cancel();
      messenger.hideCurrentMaterialBanner();
    }

    messenger
      ..clearMaterialBanners()
      ..showMaterialBanner(
        MaterialBanner(
          leading: const Icon(Symbols.swap_horiz_rounded),
          content: Text(l10n.autoSwitchedToChainBranch(branchLabel, chainLabel)),
          actions: [
            TextButton(
              onPressed: hideBanner,
              child: Text(l10n.okAction),
            ),
            TextButton(
              onPressed: () async {
                hideBanner();
                // This MainScreen is already gone (keyed by org): use the
                // router captured before the switch.
                ChainAutoSwitchSession.pause(previous.uid);
                await cacheDelegate(previous);
                ChainAutoSwitchSession.openTabAfterSwitch(1);
                router.go(homePathForRole(previous.role), extra: previous);
              },
              child: Text(l10n.autoSwitchUndo),
            ),
          ],
        ),
      );
    autoHide = Timer(const Duration(seconds: 15), hideBanner);
  }

  Future<void> _switchToOrganization(Delegate delegate) async {
    // A chain picked by hand wins over location for this login (TAS-245).
    ChainAutoSwitchSession.pause(delegate.uid);
    final cacheDelegate = di.sl<CacheDelegate>();
    await cacheDelegate(delegate);
    if (mounted) {
      final orgLabel = delegate.companyName.isNotEmpty
          ? '${delegate.organizationName} - ${delegate.companyName}'
          : delegate.organizationName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.switchedToOrg(orgLabel)),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      context.go(homePathForRole(delegate.role), extra: delegate);
    }
  }

  void _showOrgSwitcher(BuildContext context, ColorScheme colorScheme) {
    final currentDelegate = widget.delegate;
    final l10n = AppLocalizations.of(context)!;

    showM3Dialog(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          title: Row(
            children: [
              Icon(Symbols.swap_horiz_rounded, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                l10n.switchOrganization,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          children: _allDelegates.map((delegate) {
            final isCurrentOrg = delegate.uid == currentDelegate.uid &&
                delegate.organizationUID == currentDelegate.organizationUID &&
                delegate.companyUID == currentDelegate.companyUID;

            final subtitleText = delegate.companyName.trim().isNotEmpty
                ? delegate.companyName.trim()
                : (delegate.role == UserRole.marketing ||
                        delegate.role == UserRole.marketingPromotion
                    ? AppLocalizations.of(context)!.orgMarketing
                    : (delegate.role == UserRole.admin ||
                            delegate.role == UserRole.superAdmin ||
                            delegate.role == UserRole.organizationAdmin
                        ? AppLocalizations.of(context)!.orgAdminPanel
                        : (delegate.role == UserRole.accountant
                            ? AppLocalizations.of(context)!.orgAccounting
                            : '')));

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Card(
                elevation: isCurrentOrg ? 0 : 1,
                color: isCurrentOrg
                    ? colorScheme.primaryContainer
                    : colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isCurrentOrg
                      ? BorderSide(color: colorScheme.primary, width: 2)
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: Icon(
                    Symbols.business_rounded,
                    color: isCurrentOrg
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    delegate.organizationName.isNotEmpty
                        ? delegate.organizationName
                        : AppLocalizations.of(context)!.unknownOrganization,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: subtitleText.isNotEmpty
                      ? Text(
                          subtitleText,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                  trailing: isCurrentOrg
                      ? Icon(Symbols.check_circle_rounded, color: colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(dialogContext);
                    if (isCurrentOrg) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context)!.alreadyInOrg),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } else {
                      _switchToOrganization(delegate);
                    }
                  },
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// The four bottom-bar destinations (C-17).
  List<TashilDestination> _tabs(AppLocalizations l10n) => [
    TashilDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: l10n.home,
    ),
    TashilDestination(
      icon: Icons.schedule_outlined,
      selectedIcon: Icons.watch_later_rounded,
      label: l10n.attendance,
    ),
    TashilDestination(
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note_rounded,
      label: l10n.navRequests,
    ),
    TashilDestination(
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library_rounded,
      label: l10n.navPhotoReports,
    ),
  ];

  void _selectTab(int index) {
    setState(() {
      _currentIndex = index;
      _initializedTabs.add(index); // Mark tab as visited
    });
    _bar.value = true;
    if (index == 3) PhotoReportsRefresh.request();
  }

  /// TAS-350 (C-18): secondary destinations in the M3 modal navigation rail
  /// (replaces the navigation drawer, which M3 no longer recommends). The
  /// rail lists the four tabs first, then the menu entries in the same order
  /// as before (AGENTS.md menu ordering), with logout last.
  Widget _buildDrawer(
    BuildContext context,
    Delegate delegate,
    AppLocalizations l10n,
    void Function(String) onMenu,
  ) {
    final role = delegate.role;
    final entries = <(String, IconData, IconData, String)>[
      ('profile', Icons.person_outline_rounded, Icons.person_rounded,
          l10n.profile),
      ('tasks', Icons.task_alt_outlined, Icons.task_alt_rounded, l10n.tasks),
      ('penalty_rules_catalog', Icons.menu_book_outlined,
          Icons.menu_book_rounded, l10n.violationsPolicy),
      ('penalties', Icons.gavel_outlined, Icons.gavel_rounded,
          l10n.myViolations),
      if (role == UserRole.superAdmin)
        ('manage_organizations', Icons.corporate_fare_outlined,
            Icons.corporate_fare_rounded, l10n.manageOrganizationsChains),
      if (role == UserRole.superAdmin ||
          role == UserRole.technicalSupport ||
          role == UserRole.organizationAdmin)
        ('delegate_subscriptions', Icons.how_to_reg_outlined,
            Icons.how_to_reg_rounded, l10n.delegateSubscriptionsMenu),
      if (_allDelegates.length > 1)
        ('org_switch', Icons.swap_horiz_rounded, Icons.swap_horiz_rounded,
            l10n.switchOrganization),
      ('settings', Icons.settings_outlined, Icons.settings_rounded,
          l10n.settings),
      ('logout', Icons.logout_rounded, Icons.logout_rounded, l10n.logout),
    ];
    final tabs = _tabs(l10n);
    return ModalNavigationRail(
      primary: tabs,
      secondary: [
        for (final e in entries)
          TashilDestination(icon: e.$2, selectedIcon: e.$3, label: e.$4),
      ],
      selectedIndex: _currentIndex,
      onDestinationSelected: (i) {
        if (i < tabs.length) {
          _selectTab(i);
        } else {
          onMenu(entries[i - tabs.length].$1);
        }
      },
    );
  }
}
