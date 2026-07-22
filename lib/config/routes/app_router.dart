import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/pages/splash_screen.dart';
import 'package:delegate_app/features/home/presentation/pages/main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/pages/user_profile_screen.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_main_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/branch_details_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/company_details_screen.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_main_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/privacy_policy_screen.dart';
import 'package:delegate_app/features/changelog/presentation/pages/changelog_screen.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
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
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/home',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return MainScreen(delegate: delegate);
      },
    ),
    GoRoute(
      path: '/admin/home',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return AdminMainScreen(delegate: delegate);
      },
    ),
    GoRoute(
      path: '/marketing/home',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return MarketingMainScreen(delegate: delegate);
      },
    ),
    GoRoute(
      path: '/admin/branch-details',
      builder: (context, state) {
        final branch = state.extra as BranchModel;
        return BranchDetailsScreen(branch: branch);
      },
    ),
    GoRoute(
      path: '/task-details',
      builder: (context, state) {
        final extras = state.extra as Map<String, dynamic>;
        return TaskDetailsScreen(
          task: extras['task'] as TaskEntity,
          isAdmin: extras['isAdmin'] as bool,
          organizationId: extras['organizationId'] as String,
        );
      },
    ),
    GoRoute(
      path: '/privacy-policy',
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: '/changelog',
      builder: (context, state) => const ChangelogScreen(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return NotificationsPage(delegate: delegate);
      },
    ),
    GoRoute(
      path: '/submit-feedback',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return BlocProvider(
          create: (_) => di.sl<FeedbackBloc>(),
          child: SubmitFeedbackScreen(delegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/my-feedbacks',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return BlocProvider(
          create: (_) => di.sl<FeedbackBloc>(),
          child: MyFeedbacksScreen(delegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/admin/feedbacks',
      builder: (context, state) {
        return BlocProvider(
          create: (_) => di.sl<AdminFeedbackBloc>(),
          child: const AdminFeedbacksScreen(),
        );
      },
    ),
    GoRoute(
      path: '/admin/company-search',
      builder: (context, state) {
        final organizationUID = state.extra as String?;
        return CompanySearchScreen(organizationUID: organizationUID);
      },
    ),
    GoRoute(
      path: '/marketing/search',
      builder: (context, state) {
        final organizationUID = state.extra as String?;
        return MarketingSearchScreen(organizationUID: organizationUID);
      },
    ),
    GoRoute(
      path: '/user-profile',
      builder: (context, state) => const UserProfileScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return BlocProvider(
          create: (_) => di.sl<ProfileBloc>(),
          child: ProfileScreen(
            delegate: delegate,
            showBackButton: true,
          ),
        );
      },
    ),
    GoRoute(
      path: '/admin/company-details',
      builder: (context, state) {
        final company = state.extra as Company;
        return CompanyDetailsScreen(company: company);
      },
    ),
    GoRoute(
      path: '/photo-permissions/supervisor',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => di.sl<PhotoPermissionBloc>()),
            BlocProvider(create: (_) => di.sl<BranchBloc>()),
          ],
          child: SupervisorPermissionsScreen(supervisorDelegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/photo-permissions/marketing',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return BlocProvider(
          create: (_) => di.sl<PhotoPermissionBloc>(),
          child: MarketingPermissionsScreen(marketingDelegate: delegate),
        );
      },
    ),
    GoRoute(
      path: '/photo-permissions/delegate',
      builder: (context, state) {
        final delegate = state.extra as Delegate;
        return BlocProvider(
          create: (_) => di.sl<PhotoPermissionBloc>(),
          child: DelegateCameraCaptureScreen(delegate: delegate),
        );
      },
    ),
  ],
);
