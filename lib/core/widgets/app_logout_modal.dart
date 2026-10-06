import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';
import 'package:delegate_app/injection_container.dart';

/// نافذة تسجيل الخروج الموحدة المتوافقة مع معايير Material Design 3
///
/// تلتزم بالقواعد الإلزامية:
/// 1. حظر البابلز العائمة على الموبايل: عرض Modal Bottom Sheet ذكي وسلس.
/// 2. مقبض سحب علوي (Drag Handle Pill: 38px x 4.5px).
/// 3. حواف دائرية علوية (28px).
/// 4. مجموعة أزرار مدمجة ومتصلة بحاوية موحدة (Connected Action Button Group: height 48, radius 24, vertical divider).
/// 5. تكيف متجاوب للشاشات العريضة (Desktop Dialog).
/// 6. إنهاء نظيف وآمن للجلسة (إيقاف محرك التتبع، مسح توكن الإشعارات، تسجيل الخروج من فيربيز، ومسح الكاش المحلي).
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
      // 1. إيقاف جلسة التتبع الميداني فوراً لتفريغ الذاكرة وإيقاف استهلاك المعالج
      try {
        DelegateTrackingEngine().stopTrackingSession();
      } catch (e) {
        debugPrint('Logout: Error stopping tracking engine: $e');
      }

      // 2. مسح توكن إشعارات FCM الخاص بالمستخدم
      try {
        if (sl.isRegistered<PushNotificationService>()) {
          await sl<PushNotificationService>().clearToken(widget.delegate.uid);
        }
      } catch (e) {
        debugPrint('Logout: Error clearing FCM token: $e');
      }

      // 3. تسجيل الخروج من Firebase Authentication
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('Logout: Error signing out FirebaseAuth: $e');
      }

      // 4. مسح الكاش المحلي لبيانات الجلسة والمندوب
      try {
        if (sl.isRegistered<AuthRepository>()) {
          await sl<AuthRepository>().clearCache();
        }
      } catch (e) {
        debugPrint('Logout: Error clearing auth cache: $e');
      }

      if (!mounted) return;

      // إغلاق النافذة
      Navigator.of(context).pop();

      // استدعاء رد النداء الخاص إن وجد أو الانتقال لصفحة تسجيل الدخول
      if (widget.onLoggedOut != null) {
        widget.onLoggedOut!();
      } else {
        context.go('/login');
      }
    } catch (e) {
      debugPrint('Logout: Unexpected error: $e');
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تسجيل الخروج: $e'),
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
          Text(
            isArabic ? 'تسجيل الخروج' : 'Logout',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // الرسالة التوضيحية
          Text(
            isArabic
                ? 'هل أنت متأكد من تسجيل الخروج؟\nسيتم إنهاء جلستك الحالية وحفظ أي سجلات محلية بأمان.'
                : 'Are you sure you want to logout?\nYour active session will be closed safely.',
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
                Expanded(
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
                                Text(
                                  isArabic ? 'تسجيل الخروج' : 'Logout',
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
                      child: Text(
                        isArabic ? 'إلغاء' : 'Cancel',
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
