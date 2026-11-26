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
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:material_symbols_icons/symbols.dart';

class MainScreen extends StatefulWidget {
  final Delegate delegate;

  const MainScreen({super.key, required this.delegate});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

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
          if (mounted) {
            setState(() => _allDelegates = _filterDelegatesForContext(latestDelegates));
          }
        }
      });
    }
  }

  void _showLogoutDialog(BuildContext context) {
    AppLogoutModal.show(context, delegate: widget.delegate);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;
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

                return Badge(
                  label: Text('$unreadCount'),
                  isLabelVisible: unreadCount > 0,
                  child: IconButton(
                    icon: const Icon(Symbols.notifications_rounded),
                    tooltip: l10n.notifications,
                    onPressed: () {
                      context.push('/notifications', extra: delegate);
                    },
                  ),
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
          body: Column(
            children: [
              OfflineBanner(onRetry: () => setState(() {})),
              Expanded(child: _buildBody(delegate)),
            ],
          ),
          bottomNavigationBar: M3NavBar(
            selectedIndex: _currentIndex,
            onSelected: (index) {
              setState(() {
                _currentIndex = index;
                _initializedTabs.add(index); // Mark tab as visited
              });
              if (index == 3) PhotoReportsRefresh.request();
            },
            destinations: [
              M3NavDestination(icon: Symbols.home_rounded, label: l10n.home),
              M3NavDestination(
                  icon: Symbols.schedule_rounded, label: l10n.attendance),
              M3NavDestination(
                icon: Symbols.event_note_rounded,
                label: l10n.navRequests,
              ),
              M3NavDestination(
                icon: Symbols.photo_library_rounded,
                label: l10n.navPhotoReports,
              ),
            ],
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
          onNavigateToLeaves: () {
            setState(() {
              _currentIndex = 2;
              _initializedTabs.add(2);
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

  Widget _buildDrawer(
    BuildContext context,
    Delegate delegate,
    AppLocalizations l10n,
    void Function(String) onMenu,
  ) {
    final cs = Theme.of(context).colorScheme;
    final role = delegate.role;
    final entries = <(String, IconData, String)>[
      ('profile', Symbols.person_rounded, l10n.profile),
      ('tasks', Symbols.task_alt_rounded, l10n.tasks),
      ('penalty_rules_catalog', Symbols.menu_book_rounded, l10n.violationsPolicy),
      ('penalties', Symbols.gavel_rounded, l10n.myViolations),
      if (role == UserRole.superAdmin)
        ('manage_organizations', Symbols.corporate_fare_rounded,
            l10n.manageOrganizationsChains),
      if (role == UserRole.superAdmin ||
          role == UserRole.technicalSupport ||
          role == UserRole.organizationAdmin)
        ('delegate_subscriptions', Symbols.how_to_reg_rounded,
            l10n.delegateSubscriptionsMenu),
      if (_allDelegates.length > 1)
        ('org_switch', Symbols.swap_horiz_rounded, l10n.switchOrganization),
      ('settings', Symbols.settings_rounded, l10n.settings),
    ];
    final name = delegate.fullName.trim().isEmpty
        ? l10n.defaultUserName
        : delegate.fullName.trim();

    return NavigationDrawer(
      selectedIndex: null,
      onDestinationSelected: (i) {
        Navigator.of(context).pop();
        if (i < entries.length) {
          onMenu(entries[i].$1);
        } else {
          onMenu('logout');
        }
      },
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(28, 16, 16, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: Text(name.characters.first),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Divider(),
        ),
        for (final e in entries.take(entries.length - 1))
          NavigationDrawerDestination(icon: Icon(e.$2), label: Text(e.$3)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Divider(),
        ),
        NavigationDrawerDestination(
          icon: Icon(entries.last.$2),
          label: Text(entries.last.$3),
        ),
        // Red is reserved for the one destructive action.
        NavigationDrawerDestination(
          icon: Icon(Symbols.logout_rounded, color: cs.error),
          label: Text(l10n.logout, style: TextStyle(color: cs.error)),
        ),
      ],
    );
  }
}
