import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/pages/splash_screen.dart';
import 'package:delegate_app/features/home/presentation/pages/main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_main_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/branch_details_screen.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:go_router/go_router.dart';

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
      path: '/admin/branch-details',
      builder: (context, state) {
        final branch = state.extra as BranchModel;
        return BranchDetailsScreen(branch: branch);
      },
    ),
  ],
);
