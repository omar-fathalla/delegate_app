import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/auth/domain/role_home.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/splash_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/web/hr_system/web_hr_system_redirect_web.dart';

/// Signed-in user from [AuthBloc], when one is already restored.
///
/// The attendance-detail route's `extra` is the field delegate being viewed,
/// not the person who opened the shell, so the guard reads the session.
Delegate? hrShellSessionUser(BuildContext context) {
  try {
    final state = context.read<AuthBloc>().state;
    if (state is AuthAuthenticated) return state.delegate;
  } catch (_) {}
  return null;
}

/// `/hr/home`. A missing delegate still falls through to the splash, which
/// restores the session. A role that does not own the shell is sent away
/// before [HRMainScreen] is built.
Widget hrHomeRouteChild(Delegate? actor) {
  if (actor == null) return const SplashScreen();
  if (hrShellDeniedLocation(actor.role, isWeb: WebRuntimePolicy.isWeb) !=
      null) {
    return HrShellAccessGate(actor: actor);
  }
  return WebHrSystemRedirect.debugHrSystemBuilder?.call(actor) ??
      HRMainScreen(delegate: actor);
}

/// `/hr/delegate-attendance`. [subject] is the field delegate on the screen.
/// The guard uses the signed-in user. No session yet → splash, same as a
/// reload of any other signed-in route.
Widget hrAttendanceDetailRouteChild(BuildContext context, Delegate? subject) {
  if (subject == null) return const SplashScreen();
  final session = hrShellSessionUser(context);
  if (session == null) return const SplashScreen();
  if (hrShellDeniedLocation(session.role, isWeb: WebRuntimePolicy.isWeb) !=
      null) {
    return HrShellAccessGate(actor: session);
  }
  return HRDelegateAttendanceDetailScreen(
    delegate: subject,
    hrDelegate: session,
  );
}

/// Sends [actor] to [hrShellDeniedLocation] after the first frame.
/// go_router drops `extra` on a redirect, so the move stays in the widget.
class HrShellAccessGate extends StatefulWidget {
  final Delegate actor;

  const HrShellAccessGate({super.key, required this.actor});

  @override
  State<HrShellAccessGate> createState() => _HrShellAccessGateState();
}

class _HrShellAccessGateState extends State<HrShellAccessGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final location = hrShellDeniedLocation(
        widget.actor.role,
        isWeb: WebRuntimePolicy.isWeb,
      );
      if (location == null) return;
      if (location.startsWith('/login')) {
        context.go(location);
      } else {
        context.go(location, extra: widget.actor);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface);
}
