import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// هيدر مكتبي متطور للـ HR يستغل عرض الشاشات الكبيرة
class HRDesktopTopBar extends StatelessWidget {
  final Delegate delegate;
  final int activeIndex;
  final VoidCallback onRefresh;
  final ValueChanged<String> onMenuSelected;
  final List<PopupMenuEntry<String>> menuItems;

  /// Web only: notifications bell shown beside the theme button. Null keeps
  /// the mobile header unchanged.
  final Widget? webBell;

  /// Web only: account chip. Receives whether the bar is wide enough for the
  /// name. Null keeps the mobile popup menu.
  final Widget Function(bool showName)? webAccount;

  const HRDesktopTopBar({
    super.key,
    required this.delegate,
    required this.activeIndex,
    required this.onRefresh,
    required this.onMenuSelected,
    required this.menuItems,
    this.webBell,
    this.webAccount,
  });

  String _getTitle(int index) {
    switch (index) {
      case 0:
        return 'لوحة الحضور والانصراف';
      case 1:
        return 'الخريطة الحية والتتبع';
      case 2:
        return 'طلبات فك ربط الأجهزة';
      case 3:
        return 'الإجازات والاستئذانات';
      case 4:
        return 'مسيرات الرواتب الشهرية';
      case 5:
        return 'الرقابة ومكافحة الاحتيال';
      case 6:
        return 'الصور والتغطية الميدانية';
      case 7:
        return 'دليل كوادر ومناديب الشركة';
      case 8:
        return 'سجل تعديلات الحضور والانصراف';
      default:
        return hrShellHeaderTitle(index);
    }
  }

  String _getSubtitle(int index) {
    final company = delegate.companyName.isNotEmpty
        ? delegate.companyName
        : 'الشركة';
    switch (index) {
      case 0:
        return 'متابعة مباشرة ومؤتمتة لحضور وانصراف مناديب $company';
      case 1:
        return 'عرض المواقع الميدانية اللحظية ومسارات الزيارات';
      case 2:
        return 'مراجعة طلبات فك وربط الأجهزة الذكية لضمان الأمان';
      case 3:
        return 'إدارة وقبول الأعذار والإجازات والغياب الميداني';
      case 4:
        return 'احتساب ومراجعة الساعات والرواتب الشهرية';
      case 5:
        return 'التدقيق في البصمات الجغرافية واستخدام VPN أو Mock GPS';
      case 6:
        return 'أرشيف وتدقيق صور الزيارات والأرفف وأذونات التصوير';
      case 7:
        return 'قائمة مناديب ومروجي $company المسجلين بالنظام';
      case 8:
        return 'أرشيف وتدقيق كافة التعديلات الإدارية على أوقات الحضور وساعات العمل';
      default:
        return hrShellHeaderTitle(index);
    }
  }

  IconData _getIcon(int index) {
    switch (index) {
      case 0:
        return Icons.how_to_reg_rounded;
      case 1:
        return Icons.radar_rounded;
      case 2:
        return Icons.phonelink_lock_rounded;
      case 3:
        return Icons.event_note_rounded;
      case 4:
        return Icons.account_balance_wallet_rounded;
      case 5:
        return Icons.security_rounded;
      case 6:
        return Icons.photo_library_rounded;
      case 7:
        return Icons.badge_rounded;
      case 8:
        return Icons.history_edu_rounded;
      default:
        return hrShellHeaderIcon(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final now = DateTime.now();
    final arabicDate = DateFormat('EEEE، d MMMM y', 'ar').format(now);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 1024px windows still show the name (content bar is about 760px
        // beside a 260px sidebar). Tighter desktop bars keep the avatar and
        // move the name to the tooltip.
        final showName = constraints.maxWidth >= 640;
        return _bar(context, colorScheme, l10n, arabicDate, showName);
      },
    );
  }

  Widget _bar(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
    String arabicDate,
    bool showName,
  ) {
    final account = webAccount?.call(showName);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          // ── Breadcrumb / Tab Title & Subtitle ──
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getIcon(activeIndex),
              size: 20,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _getTitle(activeIndex),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'مباشر',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _getSubtitle(activeIndex),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // ── Live Date Display ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    arabicDate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // ── Refresh Button ──
          IconButton(
            key: const ValueKey('hr_web_header_refresh'),
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: onRefresh,
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHigh.withValues(
                alpha: 0.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // ── Theme Mode Toggle Button (Light/Dark Mode) ──
          BlocBuilder<ThemeCubit, ThemeState>(
            builder: (context, themeState) {
              final isDark =
                  themeState.themeMode == ThemeMode.dark ||
                  (themeState.themeMode == ThemeMode.system &&
                      MediaQuery.of(context).platformBrightness ==
                          Brightness.dark);
              return IconButton(
                tooltip: isDark ? 'الوضع النهاري' : 'الوضع الليلي',
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () => context.read<ThemeCubit>().toggleTheme(),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
          ),

          if (webBell != null) ...[const SizedBox(width: 10), webBell!],

          const SizedBox(width: 10),

          if (account != null)
            account
          else
            // ── User Menu Popup (Settings is ALWAYS the last item) ──
            PopupMenuButton<String>(
              tooltip: l10n.profile,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              offset: const Offset(0, 48),
              onSelected: onMenuSelected,
              itemBuilder: (_) => menuItems,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: AppAvatar(
                  imageUrl: delegate.personalPhotoUrl,
                  fallbackText: delegate.fullName.isNotEmpty
                      ? delegate.fullName[0]
                      : 'H',
                  radius: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
