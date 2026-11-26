import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
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

/// نافذة تسجيل الخروج الموحدة المتوافقة مع معايير Material Design 3
///
/// تلتزم بالقواعد الإلزامية:
/// 1. حظر البابلز العائمة على الموبايل: عرض Modal Bottom Sheet ذكي وسلس.
/// 2. مقبض سحب علوي (Drag Handle Pill: 38px x 4.5px).
/// 3. حواف دائرية علوية (28px).
/// 4. مجموعة أزرار مدمجة ومتصلة بحاوية موحدة (Connected Action Button Group: height 48, radius 24, vertical divider).
/// 5. تكيف متجاوب للشاشات العريضة (Desktop Dialog).
/// 6. Confirming logout dispatches [LogoutRequested]. AuthBloc signs out of
///    Firebase, clears the remember-me cache, and the app listener replaces
///    the stack with `/login`.
class AppLogoutModal {
  static Future<void> show(
    BuildContext context, {
    required Delegate delegate,
    VoidCallback? onLoggedOut,
  }) async {
    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    if (isDesktop) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _LogoutModalContent(
          delegate: delegate,
          isDesktop: true,
          onLoggedOut: onLoggedOut,
        ),
      );
    } else {
      await showM3ModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _LogoutModalContent(
          delegate: delegate,
          isDesktop: false,
          onLoggedOut: onLoggedOut,
        ),
      );
    }
  }
}

class _LogoutModalContent extends StatefulWidget {
  final Delegate delegate;
  final bool isDesktop;
  final VoidCallback? onLoggedOut;

  const _LogoutModalContent({
    required this.delegate,
    required this.isDesktop,
    this.onLoggedOut,
  });

  @override
  State<_LogoutModalContent> createState() => _LogoutModalContentState();
}

class _LogoutModalContentState extends State<_LogoutModalContent> {
  bool _isLoggingOut = false;

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    final contentWidget = Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        widget.isDesktop ? 24 : 12,
        24,
        widget.isDesktop ? 24 : (24 + MediaQuery.of(context).viewInsets.bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // مقبض السحب العلوي لشاشات الموبايل (Drag Handle Pill)
          if (!widget.isDesktop) ...[
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // أيقونة الخروج البارزة داخل حاوية دائرية مشتقة من ألوان السيمز
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.error.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.logout_rounded,
              color: colorScheme.error,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),

          // عنوان التأكيد
          Text(AppLocalizations.of(context)!.logout,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // الرسالة التوضيحية
          Text(AppLocalizations.of(context)!.logoutConfirm,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13.5,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // مجموعة الأزرار المدمجة والمتصلة بحاوية موحدة (Connected Action Button Group)
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                // زر تأكيد تسجيل الخروج
                // Maestro id: "تسجيل الخروج" is also the sheet title and the
                // Settings row, so a text tap can hit the wrong one.
                Expanded(
                  child: tashilMaestroDevSemantics(
                  identifier: 'tashil_logout_confirm_button',
                  label: 'تأكيد تسجيل الخروج',
                  button: true,
                  child: InkWell(
                    borderRadius: isArabic
                        ? const BorderRadius.horizontal(right: Radius.circular(24))
                        : const BorderRadius.horizontal(left: Radius.circular(24)),
                    onTap: _isLoggingOut ? null : _handleLogout,
                    child: Center(
                      child: _isLoggingOut
                          ? AppLoadingIndicator(
                              size: 20,
                              color: colorScheme.error,
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  size: 18,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Text(AppLocalizations.of(context)!.logout,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  ),
                ),

                // الفاصل الرأسي بين الزرين المدمجين
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),

                // زر الإلغاء
                Expanded(
                  child: InkWell(
                    borderRadius: isArabic
                        ? const BorderRadius.horizontal(left: Radius.circular(24))
                        : const BorderRadius.horizontal(right: Radius.circular(24)),
                    onTap: _isLoggingOut ? null : () => Navigator.of(context).pop(),
                    child: Center(
                      child: Text(AppLocalizations.of(context)!.cancel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.isDesktop) {
      return Dialog(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: contentWidget,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: contentWidget,
    );
  }
}
