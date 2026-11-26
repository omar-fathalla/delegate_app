import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/presentation/pages/anti_fraud_audit_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'package:delegate_app/features/admin/presentation/pages/subscription_renewal_screen.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_device_unbind_requests_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_monthly_payroll_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_delegates_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_photos_tab.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/pages/admin_penalties_list_page.dart';
import 'package:delegate_app/features/penalties/presentation/pages/penalty_rules_catalog_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/features/tracking/presentation/pages/delegate_tracking_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/web/hr_system/hr_home_overview_web.dart';

/// The existing screen for one HR-shell tab, with the same delegate the
/// supervisor menu used to push. New tools keep their own blocs and company
/// scoping; nothing here widens a query.
///
/// [photosView] lets the web shell switch «الصور» to its permissions view
/// (TAS-149).
Widget hrShellTab({
  required int index,
  required Delegate delegate,
  required ValueChanged<int> onNavigateToTab,
  HrAdjustmentsDelegateFilter? adjustmentsFilter,
  HrPhotosViewController? photosView,
}) {
  switch (index) {
    case kHrTabAttendance:
      return HRAttendanceTab(
        hrDelegate: delegate,
        onNavigateToTab: onNavigateToTab,
      );
    case kHrTabTracking:
      return DelegateTrackingScreen(
        adminDelegate: delegate,
        initialMapView: true,
        showAppBar: false,
        hrWebShell: WebRuntimePolicy.isWeb,
      );
    case kHrTabDevices:
      return HRDeviceUnbindRequestsScreen(
        hrDelegate: delegate,
        showAppBar: false,
      );
    case kHrTabLeaves:
      return HRLeavesAndExcusesScreen(hrDelegate: delegate, showAppBar: false);
    case kHrTabPayroll:
      return HRMonthlyPayrollScreen(hrDelegate: delegate, showAppBar: false);
    case kHrTabFraud:
      return AntiFraudAuditScreen(
        delegate: delegate,
        showAppBar: false,
        initialTab: 'violations',
        // Device unbind requests live on the «فك الأجهزة» tab on web.
        hrWebLayout: WebRuntimePolicy.isWeb,
      );
    case kHrTabPhotos:
      return HRPhotosTab(hrDelegate: delegate, viewController: photosView);
    case kHrTabDelegates:
      return HRDelegatesTab(hrDelegate: delegate);
    case kHrTabAdjustments:
      return HRAttendanceAdjustmentsScreen(
        hrDelegate: delegate,
        showAppBar: false,
        delegateFilter: adjustmentsFilter,
      );
    case kHrTabSubscriptions:
      return DelegateSubscriptionRequestsPage(currentAdmin: delegate);
    case kHrTabRenewal:
      return SubscriptionRenewalScreen(supervisor: delegate, showAppBar: false);
    case kHrTabTasks:
      return AdminTasksScreen(adminDelegate: delegate);
    case kHrTabPhotoPermissions:
      // Retired page (TAS-149): the shell redirects this slot to «الصور».
      return HRPhotosTab(
        hrDelegate: delegate,
        initialView: HrPhotosView.permissions,
        viewController: photosView,
      );
    case kHrTabPenaltyCatalog:
      return PenaltyRulesCatalogPage(currentDelegate: delegate);
    case kHrTabPenalties:
      return HrPenaltiesHost(admin: delegate);
    case kHrTabOverview:
      if (!WebRuntimePolicy.isWeb) return const SizedBox.shrink();
      return HrHomeOverviewWeb(
        delegate: delegate,
        onNavigateToTab: onNavigateToTab,
      );
    default:
      return const SizedBox.shrink();
  }
}

/// Penalty bloc the supervisor menu wraps around the penalties list.
///
/// On web an HR user sees every penalty in their company, read-only, like the
/// company supervisor (owner decision, TAS-156). Mobile is unchanged.
class HrPenaltiesHost extends StatelessWidget {
  final Delegate admin;

  const HrPenaltiesHost({super.key, required this.admin});

  bool get companyViewOnly =>
      WebRuntimePolicy.isWeb && admin.role == UserRole.hr;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<PenaltyBloc>(),
      child: AdminPenaltiesListPage(
        adminDelegate: admin,
        companyViewOnly: companyViewOnly,
      ),
    );
  }
}
