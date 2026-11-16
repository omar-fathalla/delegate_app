import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/pages/splash_screen.dart';
import 'package:delegate_app/features/home/presentation/pages/main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/pages/user_profile_screen.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_main_screen.dart';
import 'package:delegate_app/web/admin_desktop/admin_desktop_shell_web.dart';
import 'package:delegate_app/features/admin/presentation/pages/branch_details_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/company_details_screen.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_main_screen.dart';
import 'package:delegate_app/features/accountant/presentation/pages/accountant_main_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_login_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_main_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/privacy_policy_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/presentation/pages/task_details_loader_screen.dart';
import 'package:delegate_app/features/tasks/presentation/pages/task_details_screen.dart';
import 'package:delegate_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:delegate_app/features/feedback/presentation/pages/submit_feedback_screen.dart';
import 'package:delegate_app/features/feedback/presentation/pages/my_feedbacks_screen.dart';
import 'package:delegate_app/features/feedback/presentation/pages/admin_feedbacks_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/company_search_screen.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

// Photo Permission Feature Imports
import 'package:delegate_app/features/photo_permission/presentation/pages/supervisor_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/marketing_permissions_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/delegate_camera_capture_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/hr/presentation/pages/delegate_leaves_and_requests_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => AppMotionPage.fade(
        state: state,
        child: const SplashScreen(),
      ),
    ),
    GoRoute(
      path: '/login',
      // Splash → login: M3 fade-through (90ms out + 210ms in). The header
      // colour equals the splash colour, so only the sheet content fades in.
      pageBuilder: (context, state) => AppMotionPage.fadeThrough(
        state: state,
        child: const LoginScreen(),
      ),
    ),
    GoRoute(
      path: '/hr/login',
      pageBuilder: (context, state) => AppMotionPage.fadeThrough(
        state: state,
        child: const HrLoginScreen(),
      ),
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) {
        final delegate = state.extra is Delegate ? state.extra as Delegate : null;
        if (delegate == null) {
          return AppMotionPage.fadeThrough(
            state: state,
            child: const SplashScreen(),
          );
        }
        return AppMotionPage.fadeThrough(
          state: state,
          child: MainScreen(
            key: ValueKey('${delegate.uid}_${delegate.organizationUID}_${delegate.companyUID}'),
            delegate: delegate,
          ),
        );
      },
    ),
    GoRoute(
      path: '/admin/home',
      pageBuilder: (context, state) {
        final delegate = state.extra is Delegate ? state.extra as Delegate : null;
        // Web desktop shell page (`?p=`); kept across the splash after a reload.
        final page = state.uri.queryParameters['p'];
        if (delegate == null) {
          if (kIsWeb && AdminDesktopShellWeb.isKnownPage(page)) {
            AdminDesktopShellWeb.pendingPage = page;
          }
          return AppMotionPage.fadeThrough(
            state: state,
            child: const SplashScreen(),
          );
        }
        return AppMotionPage.fadeThrough(
          state: state,
          // Web-only desktop shell (>= 840dp); mobile/narrow keep AdminMainScreen.
          child: Builder(
            builder: (context) {
              if (!AdminDesktopShellWeb.shouldUse(context, delegate)) {
                return AdminMainScreen(delegate: delegate);
              }
              final initial = AdminDesktopShellWeb.isKnownPage(page)
                  ? page
                  : AdminDesktopShellWeb.pendingPage;
              AdminDesktopShellWeb.pendingPage = null;
              return AdminDesktopShellWeb(
                  delegate: delegate, initialPage: initial);
            },
          ),
        );
      },
    ),
    GoRoute(
      path: '/marketing/home',
      pageBuilder: (context, state) {
        final delegate = state.extra is Delegate ? state.extra as Delegate : null;
        if (delegate == null) {
          return AppMotionPage.fadeThrough(
            state: state,
            child: const SplashScreen(),
          );
        }
        return AppMotionPage.fadeThrough(
          state: state,
          child: MarketingMainScreen(delegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/accountant/home',
      pageBuilder: (context, state) {
        final delegate = state.extra is Delegate ? state.extra as Delegate : null;
        if (delegate == null) {
          return AppMotionPage.fadeThrough(
            state: state,
            child: const SplashScreen(),
          );
        }
        return AppMotionPage.fadeThrough(
          state: state,
          child: AccountantMainScreen(delegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/hr/home',
      pageBuilder: (context, state) {
        final delegate = state.extra is Delegate ? state.extra as Delegate : null;
        if (delegate == null) {
          return AppMotionPage.fadeThrough(
            state: state,
            child: const SplashScreen(),
          );
        }
        return AppMotionPage.fadeThrough(
          state: state,
          child: HRMainScreen(delegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/hr/delegate-attendance',
      pageBuilder: (context, state) {
        final delegate = state.extra is Delegate ? state.extra as Delegate : null;
        if (delegate == null) {
          return AppMotionPage.fadeThrough(
            state: state,
            child: const SplashScreen(),
          );
        }
        return AppMotionPage.fadeThrough(
          state: state,
          child: HRDelegateAttendanceDetailScreen(delegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/admin/branch-details',
      pageBuilder: (context, state) {
        final branch = state.extra as BranchModel;
        return AppMotionPage.sharedAxis(
          state: state,
          child: BranchDetailsScreen(branch: branch),
        );
      },
    ),
    GoRoute(
      path: '/task-details',
      pageBuilder: (context, state) {
        final extras = state.extra as Map<String, dynamic>;
        return AppMotionPage.sharedAxis(
          state: state,
          child: TaskDetailsScreen(
            task: extras['task'] as TaskEntity,
            isAdmin: extras['isAdmin'] as bool,
            organizationId: extras['organizationId'] as String,
            currentUserId: extras['currentUserId'] as String?,
            currentUserRole: extras['currentUserRole'] as String?,
            currentUserCompanyId: extras['currentUserCompanyId'] as String?,
            currentUserName: extras['currentUserName'] as String?,
          ),
        );
      },
    ),
    GoRoute(
      path: '/tasks/:taskId',
      pageBuilder: (context, state) {
        final taskId = state.pathParameters['taskId'] ?? '';
        final extra = state.extra;
        final delegate = extra is Delegate ? extra : null;
        return AppMotionPage.sharedAxis(
          state: state,
          child: TaskDetailsLoaderScreen(
            taskId: taskId,
            delegate: delegate,
          ),
        );
      },
    ),
    GoRoute(
      path: '/privacy-policy',
      pageBuilder: (context, state) => AppMotionPage.sharedAxis(
        state: state,
        child: const PrivacyPolicyScreen(),
      ),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) {
        final delegate = state.extra is Delegate ? state.extra as Delegate : null;
        if (delegate == null) {
          return AppMotionPage.sharedAxis(
            state: state,
            child: const SplashScreen(),
          );
        }
        return AppMotionPage.sharedAxis(
          state: state,
          child: SettingsScreen(
            delegate: delegate,
            showAppBar: true,
          ),
        );
      },
    ),
    GoRoute(
      path: '/notifications',
      pageBuilder: (context, state) {
        final delegate = state.extra as Delegate;
        return AppMotionPage.sharedAxis(
          state: state,
          child: NotificationsPage(delegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/submit-feedback',
      pageBuilder: (context, state) {
        final delegate = state.extra as Delegate;
        return AppMotionPage.sharedAxis(
          state: state,
          child: BlocProvider(
            create: (_) => di.sl<FeedbackBloc>(),
            child: SubmitFeedbackScreen(delegate: delegate),
          ),
        );
      },
    ),
    GoRoute(
      path: '/my-feedbacks',
      pageBuilder: (context, state) {
        final delegate = state.extra as Delegate;
        return AppMotionPage.sharedAxis(
          state: state,
          child: BlocProvider(
            create: (_) => di.sl<FeedbackBloc>(),
            child: MyFeedbacksScreen(delegate: delegate),
          ),
        );
      },
    ),
    GoRoute(
      path: '/admin/feedbacks',
      pageBuilder: (context, state) {
        return AppMotionPage.sharedAxis(
          state: state,
          child: BlocProvider(
            create: (_) => di.sl<AdminFeedbackBloc>(),
            child: const AdminFeedbacksScreen(),
          ),
        );
      },
    ),
    GoRoute(
      path: '/admin/company-search',
      pageBuilder: (context, state) {
        final organizationUID = state.extra as String?;
        return AppMotionPage.sharedAxis(
          state: state,
          child: CompanySearchScreen(organizationUID: organizationUID),
        );
      },
    ),
    GoRoute(
      path: '/marketing/search',
      pageBuilder: (context, state) {
        final organizationUID = state.extra as String?;
        return AppMotionPage.sharedAxis(
          state: state,
          child: MarketingSearchScreen(organizationUID: organizationUID),
        );
      },
    ),
    GoRoute(
      path: '/user-profile',
      pageBuilder: (context, state) {
        final delegate = state.extra is Delegate ? state.extra as Delegate : null;
        return AppMotionPage.sharedAxis(
          state: state,
          child: UserProfileScreen(delegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) {
        final delegate = state.extra as Delegate;
        return AppMotionPage.sharedAxis(
          state: state,
          child: BlocProvider(
            create: (_) => di.sl<ProfileBloc>(),
            child: ProfileScreen(
              delegate: delegate,
              showBackButton: true,
            ),
          ),
        );
      },
    ),
    GoRoute(
      path: '/admin/company-details',
      pageBuilder: (context, state) {
        final company = state.extra as Company;
        return AppMotionPage.sharedAxis(
          state: state,
          child: CompanyDetailsScreen(company: company),
        );
      },
    ),
    GoRoute(
      path: '/photo-permissions/supervisor',
      pageBuilder: (context, state) {
        final delegate = state.extra as Delegate;
        return AppMotionPage.sharedAxis(
          state: state,
          child: MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => di.sl<PhotoPermissionBloc>()),
              BlocProvider(create: (_) => di.sl<BranchBloc>()),
            ],
            child: SupervisorPermissionsScreen(supervisorDelegate: delegate),
          ),
        );
      },
    ),
    GoRoute(
      path: '/photo-permissions/marketing',
      pageBuilder: (context, state) {
        final delegate = state.extra as Delegate;
        return AppMotionPage.sharedAxis(
          state: state,
          child: BlocProvider(
            create: (_) => di.sl<PhotoPermissionBloc>(),
            child: MarketingPermissionsScreen(marketingDelegate: delegate),
          ),
        );
      },
    ),
    GoRoute(
      path: '/photo-permissions/delegate',
      pageBuilder: (context, state) {
        final delegate = state.extra as Delegate;
        return AppMotionPage.sharedAxis(
          state: state,
          child: BlocProvider(
            create: (_) => di.sl<PhotoPermissionBloc>(),
            child: DelegateCameraCaptureScreen(delegate: delegate),
          ),
        );
      },
    ),
    GoRoute(
      path: '/delegate/leaves-and-requests',
      pageBuilder: (context, state) {
        final delegate = state.extra as Delegate;
        return AppMotionPage.sharedAxis(
          state: state,
          child: DelegateLeavesAndRequestsScreen(delegate: delegate),
        );
      },
    ),
  ],
);
