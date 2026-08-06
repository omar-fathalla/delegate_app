import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/supervisor_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/marketing_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/super_admin_permissions_report_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_payment_receipts_report_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_branch_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_branches_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/create_admin_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_dashboard_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/manage_admins_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/manage_marketing_screen.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_penalties_list_page.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_delegates_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';


class AdminMainScreen extends StatefulWidget {
  final Delegate delegate;

  const AdminMainScreen({super.key, required this.delegate});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    final delegate = widget.delegate;
    if (isSuperAdmin) {
      _screens = [
        SuperAdminDashboardScreen(
          delegate: delegate,
          onNavigateToBranches: () => setState(() => _currentIndex = 1),
          onNavigateToAddBranch: () => setState(() => _currentIndex = 2),
          onNavigateToCreateAdmin: () => setState(() => _currentIndex = 3),
        ),
        const AdminBranchesScreen(),
        const AddBranchScreen(),
        CreateAdminScreen(organizationUID: delegate.organizationUID),
      ];
    } else if (isOrganizationAdmin) {
      _screens = [
        AdminHomeScreen(adminDelegate: delegate),
        AdminTasksScreen(adminDelegate: delegate),
        // تبويب أذونات التصوير
        BlocProvider(
          create: (_) => di.sl<PhotoPermissionBloc>()
            ..add(const LoadPermissionsRequested(
              organizationUID: '',
              companyUID: '',
            )),
          child: MarketingPermissionsScreen(marketingDelegate: delegate),
        ),
        // تبويب المخالفات والغرامات (قراءة + إضافة لمشرف الشركات)
        BlocProvider(
          create: (_) => di.sl<PenaltyBloc>(),
          child: CompanyPenaltiesSettingsPage(delegate: delegate),
        ),
      ];
    } else {
      _screens = [
        AdminHomeScreen(adminDelegate: delegate),
        AdminDelegatesScreen(adminDelegate: delegate),
        AdminTasksScreen(adminDelegate: delegate),
        MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => di.sl<PhotoPermissionBloc>()),
            BlocProvider(create: (_) => di.sl<BranchBloc>()),
          ],
          child: SupervisorPermissionsScreen(
            supervisorDelegate: delegate,
            showAppBar: false,
          ),
        ),
      ];
    }
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'manage_admins':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ManageAdminsScreen()));
        break;
      case 'manage_marketing':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ManageMarketingScreen()));
        break;
      case 'manage_feedbacks':
        context.push('/admin/feedbacks');
        break;
      case 'permissions_report':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => di.sl<PhotoPermissionBloc>(),
              child: SuperAdminPermissionsReportScreen(delegate: widget.delegate),
            ),
          ),
        );
        break;
      case 'receipts_report':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SuperAdminPaymentReceiptsReportScreen(delegate: widget.delegate),
          ),
        );
        break;
      case 'penalties_management':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider(
              create: (_) => di.sl<PenaltyBloc>(),
              child: AdminPenaltiesListPage(adminDelegate: widget.delegate),
            ),
          ),
        );
        break;
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              delegate: widget.delegate,
              showAppBar: true,
            ),
          ),
        );
        break;
      case 'profile':
        context.push('/user-profile');
        break;
    }
  }

  bool get isSuperAdmin => widget.delegate.role == UserRole.superAdmin;
  bool get isOrganizationAdmin =>
      widget.delegate.role == UserRole.organizationAdmin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;

    final headerTitle = isSuperAdmin ? null : delegate.companyName;

    final subtitle = isSuperAdmin
        ? (_currentIndex == 0
              ? l10n.home
              : _currentIndex == 1
              ? l10n.adminUser(delegate.firstName)
              : _currentIndex == 2
              ? l10n.addBranch
              : l10n.createAdmin)
        : isOrganizationAdmin
        ? (_currentIndex == 0
              ? delegate.firstName
              : _currentIndex == 1
              ? l10n.tasks
              : _currentIndex == 2
              ? 'أذونات التصوير'
              : 'المخالفات والغرامات')
        : (_currentIndex == 0
              ? l10n.supervisorUser(delegate.firstName)
              : _currentIndex == 1
              ? l10n.companyDelegates
              : _currentIndex == 2
              ? l10n.tasks
              : l10n.photoPermissions);

    return Scaffold(
      appBar: AdminHeader(
        title: headerTitle,
        subtitle: subtitle,
        actions: [
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
        ],
        menuItems: [
          if (isSuperAdmin) ...[
            PopupMenuItem(
              value: 'manage_admins',
              child: ListTile(
                leading: const Icon(Icons.group_rounded),
                title: Text(l10n.manageAdmins),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'manage_marketing',
              child: ListTile(
                leading: const Icon(Icons.campaign_rounded),
                title: Text(l10n.manageMarketing),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'manage_feedbacks',
              child: ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('إدارة المقترحات'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'permissions_report',
              child: ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('تقرير أذونات التصوير'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'receipts_report',
              child: ListTile(
                leading: const Icon(Icons.receipt_long_rounded),
                title: Text(l10n.receiptsReport),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],

          // نظام الغرامات في القائمة للـ superAdmin و admin (للـ organizationAdmin موجود كتبويب مباشر)
          if (!isOrganizationAdmin) ...[
            const PopupMenuItem(
              value: 'penalties_management',
              child: ListTile(
                leading: Icon(Icons.gavel_rounded),
                title: Text('نظام الغرامات والمخالفات'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          PopupMenuItem(
            value: 'profile',
            child: ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('الملف الشخصي'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'settings',
            child: ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: Text(l10n.settings),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
        onMenuSelected: _onMenuSelected,
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: isSuperAdmin
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.storefront_rounded),
                  label: l10n.branches,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: l10n.addBranch,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.admin_panel_settings_rounded),
                  label: l10n.createAdmin,
                ),
              ],
            )
          : isOrganizationAdmin
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.task_alt_outlined),
                  selectedIcon: const Icon(Icons.task_alt_rounded),
                  label: l10n.tasks,
                ),
                const NavigationDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library_rounded),
                  label: 'أذونات التصوير',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.gavel_outlined),
                  selectedIcon: Icon(Icons.gavel_rounded),
                  label: 'الغرامات',
                ),
              ],
            )
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: l10n.home,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.people_outline_rounded),
                  selectedIcon: const Icon(Icons.people_rounded),
                  label: l10n.companyDelegates,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.task_alt_outlined),
                  selectedIcon: const Icon(Icons.task_alt_rounded),
                  label: l10n.tasks,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.collections_outlined),
                  selectedIcon: const Icon(Icons.collections_rounded),
                  label: l10n.photoPermissions,
                ),
              ],
            ),
    );
  }
}
