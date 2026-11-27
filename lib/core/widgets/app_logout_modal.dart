import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/widgets/tashil_maestro_dev_semantics.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_bloc.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/core/services/sync_manager.dart';

/// Logout confirmation (TAS-350, m3-kit C-27): a basic M3 [AlertDialog]
/// opened with [showTashilDialog] on every window size and for every role.
///
/// The headline is the question, the body says what happens, and the two
/// text buttons are "إلغاء" then the confirm button named after its result,
/// so in Arabic the confirm sits at the end (left). Confirming dispatches
/// [LogoutRequested]: AuthBloc signs out of Firebase, clears the remember-me
/// cache, and the app listener replaces the stack with `/login`.
/// `tashil_logout_confirm_button` stays for the Maestro journeys (TAS-192).
class AppLogoutModal {
  static Future<void> show(
    BuildContext context, {
    required Delegate delegate,
    VoidCallback? onLoggedOut,
  }) {
    return showTashilDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _LogoutDialog(delegate: delegate, onLoggedOut: onLoggedOut),
    );
  }
}

class _LogoutDialog extends StatefulWidget {
  final Delegate delegate;
  final VoidCallback? onLoggedOut;

  const _LogoutDialog({required this.delegate, this.onLoggedOut});

  @override
  State<_LogoutDialog> createState() => _LogoutDialogState();
}

class _LogoutDialogState extends State<_LogoutDialog> {
  bool _isLoggingOut = false;

  /// TAS-369 (message 5.3): photos of this delegate still on the phone.
  /// They are kept for the next sign-in, but warn before leaving.
  int get _pendingPhotos {
    try {
      if (!sl.isRegistered<SyncManager>()) return 0;
      return sl<SyncManager>().statusNotifier.value.pendingCount;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      try {
        DelegateTrackingEngine().stopTrackingSession();
      } catch (e) {
        debugPrint('Logout: Error stopping tracking engine: $e');
      }

      final bloc = context.read<AuthBloc>();
      final loggedOut = bloc.stream.firstWhere(
        (state) => state is AuthUnauthenticated && state.fromLogout,
      );
      bloc.add(LogoutRequested(userId: widget.delegate.uid));
      try {
        await loggedOut.timeout(const Duration(seconds: 6));
      } catch (_) {}

      // مسح الكاش المحلي للحضور والـ blocs (تغييرات محلية)
      try {
        if (sl.isRegistered<AttendanceLocalDataSource>()) {
          await sl<AttendanceLocalDataSource>().clearAttendanceCache();
        }
        AttendanceBloc.clearCache();
        AdminDelegatesBloc.clearCache();
        AdminDashboardBloc.clearCache();
        MarketingBloc.clearCache();
      } catch (e) {
        debugPrint('Logout: Error clearing attendance cache: $e');
      }

      if (!mounted) return;
      // Replacing the stack with /login — do not pop(). After the auth
      // listener (or this go) already moved to login, a pop would hit
      // go_router's "popped the last page off of the stack" and leave
      // a black screen (M31 ce97cb3).
      context.go('/login');
      widget.onLoggedOut?.call();
    } catch (e) {
      debugPrint('Logout: Unexpected error: $e');
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.logoutFailed(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isLoggingOut,
      child: AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: Text(l10n.logoutDialogTitle),
        content: _pendingPhotos > 0
            ? Text(
                l10n.logoutPendingPhotosWarning(_pendingPhotos),
                key: const Key('logout_pending_photos_warning'),
              )
            : Text(l10n.logoutDialogBody),
        actions: [
          TextButton(
            onPressed: _isLoggingOut ? null : () => Navigator.of(context).pop(),
            child: Text(_pendingPhotos > 0 ? l10n.logoutWaitForPhotos : l10n.cancel),
          ),
          tashilMaestroDevSemantics(
            identifier: 'tashil_logout_confirm_button',
            label: 'تأكيد تسجيل الخروج',
            button: true,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: cs.error),
              onPressed: _isLoggingOut ? null : _handleLogout,
              child: _isLoggingOut
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: l10n.logout,
                      ),
                    )
                  : Text(_pendingPhotos > 0 ? l10n.logoutAnyway : l10n.logout),
            ),
          ),
        ],
      ),
    );
  }
}
