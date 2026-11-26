import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/pages/submit_feedback_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/pages/user_profile_screen.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// Account pages of the HR shell: settings, profile and send feedback
/// (TAS-157).
///
/// Inside the wide web shell (a [HrInnerPageHost] above [context]) they open
/// as inner pages with a 720 content width, so the sidebar and the top bar
/// stay. Everywhere else (mobile, narrow web, other shells) they open
/// exactly as before.
abstract final class HrAccountPages {
  static const String settingsTitle = 'الإعدادات';
  static const String profileTitle = 'الملف الشخصي';
  static const String feedbackTitle = 'إرسال ملاحظات';

  /// Tests replace the profile page, which needs Firebase Auth.
  @visibleForTesting
  static Widget Function(Delegate delegate, bool inShell)? debugProfileBuilder;

  /// Tests replace the feedback page, which needs the feedback bloc.
  @visibleForTesting
  static Widget Function(Delegate delegate, bool inShell)? debugFeedbackBuilder;

  /// Wide web shell (inner navigator) or narrow web shell (tracker,
  /// TAS-189): open through [pushHrInnerPage] so the URL counts the page.
  static bool _hasHost(BuildContext context) =>
      HrInnerPageHost.maybeOf(context)?.navigatorKey.currentState != null ||
      HrInnerPageTracker.maybeOf(context) != null;

  static Future<void> openSettings(BuildContext context, Delegate delegate) {
    if (!_hasHost(context)) {
      return Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SettingsScreen(delegate: delegate, showAppBar: true),
        ),
      );
    }
    return pushHrInnerPage<void>(
      context,
      title: settingsTitle,
      builder: (_, inShell) =>
          SettingsScreen(delegate: delegate, showAppBar: !inShell),
    );
  }

  static Future<void> openProfile(BuildContext context, Delegate delegate) {
    if (!_hasHost(context)) {
      return context.push<void>('/user-profile', extra: delegate);
    }
    return pushHrInnerPage<void>(
      context,
      title: profileTitle,
      builder: (_, inShell) =>
          debugProfileBuilder?.call(delegate, inShell) ??
          UserProfileScreen(delegate: delegate, showAppBar: !inShell),
    );
  }

  static Future<void> openSendFeedback(
    BuildContext context,
    Delegate delegate,
  ) {
    if (!_hasHost(context)) {
      return context.push<void>('/submit-feedback', extra: delegate);
    }
    return pushHrInnerPage<void>(
      context,
      title: feedbackTitle,
      builder: (_, inShell) =>
          debugFeedbackBuilder?.call(delegate, inShell) ??
          BlocProvider(
            create: (_) => di.sl<FeedbackBloc>(),
            child: SubmitFeedbackScreen(
              delegate: delegate,
              showAppBar: !inShell,
            ),
          ),
    );
  }
}
