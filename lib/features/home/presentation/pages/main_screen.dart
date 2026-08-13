import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/features/home/presentation/pages/delegate_home_screen.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_bloc.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_event.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_state.dart';
import 'package:delegate_app/features/changelog/presentation/widgets/whats_new_dialog.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_delegate.dart';
import 'package:delegate_app/features/tasks/presentation/pages/delegate_tasks_screen.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';

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

  @override
  void initState() {
    super.initState();
    _loadAllDelegates();
  }

  Future<void> _loadAllDelegates() async {
    final result = await di.sl<AuthRepository>().getCachedAllDelegates();
    result.fold((_) {}, (delegates) {
      if (mounted) setState(() => _allDelegates = delegates);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;

    return BlocProvider(
      create: (_) {
        final bloc = di.sl<ChangelogBloc>();
        Future.delayed(const Duration(seconds: 4), () {
          if (!bloc.isClosed) {
            bloc.add(CheckForNewUpdates());
          }
        });
        return bloc;
      },
      child: BlocListener<ChangelogBloc, ChangelogState>(
        listener: (context, state) {
          if (state is ChangelogHasNewUpdates) {
            // Show the dialog after the frame is built
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              WhatsNewDialog.show(
                context,
                updates: state.updates,
                onDismiss: () {
                  context.read<ChangelogBloc>().add(DismissNewUpdates());
                },
              );
            });
          }
        },
        child: Scaffold(
          appBar: AppBar(
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.onSurface,
                  surfaceTintColor: colorScheme.surfaceTint,
                  title: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.helloUser(delegate.firstName),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              delegate.organizationName,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    // Notification Bell with Badge
                    BlocProvider(
                      create: (_) => di.sl<NotificationBloc>()
                        ..add(
                          SubscribeToUnreadCount(
                            delegateUid: delegate.uid,
                            organizationId: delegate.organizationUID,
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
                              icon: const Icon(Icons.notifications_outlined),
                              tooltip: l10n.notifications,
                              onPressed: () {
                                context.push('/notifications', extra: delegate);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Header Menu (Profile, Settings, Org Switcher)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.menu_rounded),
                      tooltip: isArabic ? 'القائمة' : 'Menu',
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onSelected: (value) {
                        if (value == 'profile') {
                          context.push('/profile', extra: delegate);
                        } else if (value == 'settings') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(
                                delegate: delegate,
                                showAppBar: true,
                              ),
                            ),
                          );
                        } else if (value == 'penalties') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BlocProvider(
                                create: (_) => di.sl<PenaltyBloc>()
                                  ..add(LoadCompanyPenaltiesEvent(delegate.companyUID)),
                                child: CompanyPenaltiesSettingsPage(
                                  delegate: delegate,
                                  showAppBar: true,
                                ),
                              ),
                            ),
                          );
                        } else if (value == 'org_switch') {
                          _showOrgSwitcher(context, colorScheme);
                        }
                      },
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'profile',
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline_rounded),
                              const SizedBox(width: 12),
                              Text(l10n.profile),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'settings',
                          child: Row(
                            children: [
                              const Icon(Icons.settings_outlined),
                              const SizedBox(width: 12),
                              Text(l10n.settings),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'penalties',
                          child: Row(
                            children: [
                              Icon(Icons.gavel_rounded, color: colorScheme.error),
                              const SizedBox(width: 12),
                              const Text('المخالفات والغرامات'),
                            ],
                          ),
                        ),
                        if (_allDelegates.length > 1) ...[
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: 'org_switch',
                            child: Row(
                              children: [
                                const Icon(Icons.swap_horiz_rounded),
                                const SizedBox(width: 12),
                                Text(isArabic ? 'تبديل المنظمة' : 'Switch Organization'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
          body: _buildBody(delegate),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
                _initializedTabs.add(index); // Mark tab as visited
              });
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_rounded),
                label: isArabic ? 'الرئيسية' : 'Home',
              ),
              NavigationDestination(
                icon: const Icon(Icons.access_time_filled),
                label: l10n.attendance,
              ),
              NavigationDestination(
                icon: const Icon(Icons.task_alt_rounded),
                label: l10n.tasks,
              ),
              NavigationDestination(
                icon: const Icon(Icons.photo_library_rounded),
                label: isArabic ? 'تقارير الصور' : 'Photo Report',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lazy-builds tabs: only creates a tab widget when it's first visited,
  /// then keeps it alive via IndexedStack so it isn't destroyed on tab switch.
  Widget _buildBody(Delegate delegate) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        // Tab 0: Home (always initialized)
        DelegateHomeScreen(delegate: delegate),

        // Tab 1: Attendance
        if (_initializedTabs.contains(1))
          AttendanceScreen(delegate: delegate)
        else
          const SizedBox.shrink(),

        // Tab 2: Tasks
        if (_initializedTabs.contains(2))
          BlocProvider(
            create: (context) => di.sl<DelegateTasksBloc>(),
            child: DelegateTasksScreen(delegate: delegate),
          )
        else
          const SizedBox.shrink(),

        // Tab 3: Photo Reports
        if (_initializedTabs.contains(3))
          BlocProvider(
            create: (context) => di.sl<PhotoPermissionBloc>(),
            child: MonthlyPhotoReportScreen(delegate: delegate),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Future<void> _switchToOrganization(Delegate delegate) async {
    final cacheDelegate = di.sl<CacheDelegate>();
    await cacheDelegate(delegate);
    if (mounted) {
      context.go('/home', extra: delegate);
    }
  }

  void _showOrgSwitcher(BuildContext context, ColorScheme colorScheme) {
    final isArabic = localeProvider.isArabic;
    final currentDelegate = widget.delegate;

    showDialog(
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
              Icon(Icons.swap_horiz_rounded, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                isArabic ? 'تبديل المنظمة' : 'Switch Organization',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          children: _allDelegates.map((delegate) {
            final isCurrentOrg = delegate.uid == currentDelegate.uid;
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
                    Icons.business_rounded,
                    color: isCurrentOrg
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    delegate.organizationName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    delegate.companyName,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: isCurrentOrg
                      ? Icon(Icons.check_circle, color: colorScheme.primary)
                      : null,
                  onTap: isCurrentOrg
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          _switchToOrganization(delegate);
                        },
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
