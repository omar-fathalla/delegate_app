import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/home/presentation/pages/delegate_home_screen.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
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

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate.organizationUID != widget.delegate.organizationUID ||
        oldWidget.delegate.companyUID != widget.delegate.companyUID ||
        oldWidget.delegate.uid != widget.delegate.uid) {
      setState(() {
        _currentIndex = 0;
        _initializedTabs.clear();
        _initializedTabs.add(0);
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
      final remoteResult =
          await di.sl<AuthRepository>().getDelegatesByPhone(widget.delegate.phoneNumber);
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
    final isArabic = localeProvider.isArabic;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
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
                    icon: const Icon(Icons.notifications_rounded),
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
        onMenuSelected: (value) {
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
        },
        menuItems: [
          PopupMenuItem<String>(
            value: 'profile',
            child: Row(
              children: [
                const Icon(Icons.person_rounded),
                const SizedBox(width: 12),
                Text(l10n.profile),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'penalty_rules_catalog',
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded, color: colorScheme.primary),
                const SizedBox(width: 12),
                const Text('لائحة الغرامات'),
              ],
            ),
          ),
          if (delegate.role == UserRole.superAdmin) ...[
            PopupMenuItem<String>(
              value: 'manage_organizations',
              child: Row(
                children: [
                  Icon(Icons.corporate_fare_rounded, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text('إدارة المنظمات والسلاسل'),
                ],
              ),
            ),
          ],
          if (delegate.role == UserRole.superAdmin ||
              delegate.role == UserRole.technicalSupport ||
              delegate.role == UserRole.organizationAdmin) ...[
            PopupMenuItem<String>(
              value: 'delegate_subscriptions',
              child: Row(
                children: [
                  Icon(Icons.how_to_reg_rounded, color: colorScheme.tertiary),
                  const SizedBox(width: 12),
                  const Text('اشتراكات واعتماد المناديب'),
                ],
              ),
            ),
          ],
          if (_allDelegates.length > 1) ...[
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
          PopupMenuItem<String>(
            value: 'tasks',
            child: Row(
              children: [
                Icon(Icons.task_alt_rounded, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(l10n.tasks),
              ],
            ),
          ),
          // المخالفات والغرامات دائماً فوق تسجيل الخروج لتطابق اللون والتنسيق
          PopupMenuItem<String>(
            value: 'penalties',
            child: Row(
              children: [
                Icon(Icons.gavel_rounded, color: colorScheme.error),
                const SizedBox(width: 12),
                Text(
                  'المخالفات والغرامات',
                  style: TextStyle(color: colorScheme.error),
                ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout_rounded, color: colorScheme.error),
                const SizedBox(width: 12),
                Text(l10n.logout, style: TextStyle(color: colorScheme.error)),
              ],
            ),
          ),
          const PopupMenuDivider(),
          // الإعدادات دائماً في أسفل القائمة
          PopupMenuItem<String>(
            value: 'settings',
            child: Row(
              children: [
                const Icon(Icons.settings_rounded),
                const SizedBox(width: 12),
                Text(l10n.settings),
              ],
            ),
          ),
        ],
      ),
          body: _buildBody(delegate),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
            ),
            child: NavigationBar(
              backgroundColor: colorScheme.surfaceContainer,
              elevation: 0,
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
                  icon: const Icon(Icons.access_time_filled_rounded),
                  label: l10n.attendance,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.event_note_rounded),
                  label: isArabic ? 'طلباتي' : 'My Requests',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.photo_library_rounded),
                  label: isArabic ? 'تقارير الصور' : 'Photo Report',
                ),
              ],
            ),
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
          AttendanceScreen(delegate: delegate)
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
      final orgLabel = delegate.companyName.isNotEmpty
          ? '${delegate.organizationName} - ${delegate.companyName}'
          : delegate.organizationName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم التبديل بنجاح إلى: $orgLabel'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (delegate.role == UserRole.admin ||
          delegate.role == UserRole.superAdmin ||
          delegate.role == UserRole.organizationAdmin ||
          delegate.role == UserRole.technicalSupport ||
          delegate.role == UserRole.branchesMarketingManager) {
        context.go('/admin/home', extra: delegate);
      } else if (delegate.role == UserRole.accountant) {
        context.go('/accountant/home', extra: delegate);
      } else if (delegate.role == UserRole.hr) {
        context.go('/hr/home', extra: delegate);
      } else if (delegate.role == UserRole.marketing ||
          delegate.role == UserRole.marketingPromotion) {
        context.go('/marketing/home', extra: delegate);
      } else {
        context.go('/home', extra: delegate);
      }
    }
  }

  void _showOrgSwitcher(BuildContext context, ColorScheme colorScheme) {
    final isArabic = localeProvider.isArabic;
    final currentDelegate = widget.delegate;

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
            final isCurrentOrg = delegate.uid == currentDelegate.uid &&
                delegate.organizationUID == currentDelegate.organizationUID &&
                delegate.companyUID == currentDelegate.companyUID;

            final subtitleText = delegate.companyName.trim().isNotEmpty
                ? delegate.companyName.trim()
                : (delegate.role == UserRole.marketing ||
                        delegate.role == UserRole.marketingPromotion
                    ? (isArabic ? 'إدارة التسويق' : 'Marketing Department')
                    : (delegate.role == UserRole.admin ||
                            delegate.role == UserRole.superAdmin ||
                            delegate.role == UserRole.organizationAdmin
                        ? (isArabic ? 'لوحة الإدارة' : 'Admin Panel')
                        : (delegate.role == UserRole.accountant
                            ? (isArabic ? 'الحسابات والمالية' : 'Accounting')
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
                    Icons.business_rounded,
                    color: isCurrentOrg
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    delegate.organizationName.isNotEmpty
                        ? delegate.organizationName
                        : 'منظمة غير محددة',
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
                      ? Icon(Icons.check_circle_rounded, color: colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(dialogContext);
                    if (isCurrentOrg) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('أنت تعمل بالفعل ضمن هذه المنظمة حالياً.'),
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
}
