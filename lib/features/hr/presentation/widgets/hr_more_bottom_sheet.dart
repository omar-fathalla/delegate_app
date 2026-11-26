import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/widgets/keyed_stream_builder.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// بيانات عنصر في قائمة "المزيد" لمسؤولي الموارد البشرية والمشرفين
class HRMoreItemData {
  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;
  final String? badgeCollection;

  const HRMoreItemData({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedIcon,
    this.badgeCollection,
  });
}

/// نافذة سفلية منبثقة بتصميم Material Design 3 لعرض الأقسام الإضافية في نظام الموارد البشرية
class HRMoreBottomSheet extends StatelessWidget {
  final Delegate hrDelegate;
  final int currentIndex;
  final ValueChanged<int> onSelectTab;

  const HRMoreBottomSheet({
    super.key,
    required this.hrDelegate,
    required this.currentIndex,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final items = WebRuntimePolicy.isWeb ? _webItems() : _mobileItems();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(HrRadius.pill)),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // M3 Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(HrRadius.chip),
                  ),
                ),
              ),

              // Bottom Sheet Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.7,
                        ),
                        borderRadius: BorderRadius.circular(HrRadius.card),
                      ),
                      child: Icon(
                        Icons.grid_view_rounded,
                        color: colorScheme.onPrimaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المزيد من الأقسام والخدمات',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اختر القسم المطلوب للمتابعة وإدارة العمليات',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'إغلاق',
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHigh,
                        foregroundColor: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Divider(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                height: 1,
                thickness: 0.8,
              ),
              const SizedBox(height: 8),

              // List of More Items
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = currentIndex == item.index;

                    return _buildMoreItemTile(
                      context: context,
                      item: item,
                      isSelected: isSelected,
                      colorScheme: colorScheme,
                      textTheme: textTheme,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<HRMoreItemData> _mobileItems() => const [
    HRMoreItemData(
      index: 4,
      title: 'مسير الرواتب والعمولات',
      subtitle: 'كشوف الحسابات الشهرية والبدلات والسلف والمكافآت',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
    ),
    HRMoreItemData(
      index: 2,
      title: 'طلبات فك وربط الأجهزة',
      subtitle: 'اعتماد ومراجعة طلبات تغيير الهواتف المقيدة للمناديب',
      icon: Icons.phonelink_lock_outlined,
      selectedIcon: Icons.phonelink_lock_rounded,
      badgeCollection: 'device_unbind_requests',
    ),
    HRMoreItemData(
      index: 5,
      title: 'تدقيق الأمان ومكافحة الاحتيال',
      subtitle: 'رصد محاولات التلاعب بالموقع الجغرافي والروت والمحاكاة',
      icon: Icons.security_outlined,
      selectedIcon: Icons.security_rounded,
    ),
    HRMoreItemData(
      index: 6,
      title: 'الصور والزيارات الميدانية',
      subtitle: 'معرض صور إثبات الحضور والزيارات وتوثيق الفروع',
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library_rounded,
    ),
    HRMoreItemData(
      index: 8,
      title: 'سجل تعديلات الحضور والانصراف',
      subtitle: 'مراجعة وتدقيق التعديلات اليدوية المعتمدة على البصمات',
      icon: Icons.history_edu_outlined,
      selectedIcon: Icons.history_edu_rounded,
    ),
  ];

  List<HRMoreItemData> _webItems() => [
    for (final item in hrShellItems(
      delegate: hrDelegate,
      isWeb: true,
      placement: HrShellPlacement.moreSheet,
    ))
      HRMoreItemData(
        index: item.tabIndex!,
        title: item.menuLabel(isWeb: true),
        subtitle: item.subtitle,
        icon: item.icon,
        selectedIcon: item.selectedIcon,
        badgeCollection: item.badgeCollection,
      ),
  ];

  Widget _buildMoreItemTile({
    required BuildContext context,
    required HRMoreItemData item,
    required bool isSelected,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(HrRadius.card),
        onTap: () {
          Navigator.pop(context);
          onSelectTab(item.index);
        },
        child: AnimatedContainer(
          duration: AppMotionDurations.short4,
          curve: AppMotionCurves.standardDecelerate,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(HrRadius.card),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.7)
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
              width: isSelected ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            children: [
              // Icon Box with optional live badge
              _buildIconWithBadge(item, isSelected, colorScheme),
              const SizedBox(width: 14),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        fontSize: HrFont.body,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: HrFont.labelSmall,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Trailing Indicator
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: colorScheme.onPrimary,
                    size: 14,
                  ),
                )
              else
                Icon(
                  Icons.chevron_left_rounded,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconWithBadge(
    HRMoreItemData item,
    bool isSelected,
    ColorScheme colorScheme,
  ) {
    Widget icon = Icon(
      isSelected ? item.selectedIcon : item.icon,
      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      size: 22,
    );

    final badgeCollection = item.badgeCollection;
    if (badgeCollection != null) {
      final companyUID = hrDelegate.companyUID;
      // Created once per (collection, company), not on every build (TAS-90).
      // If Firebase isn't ready the error leaves the count at zero.
      icon = KeyedStreamBuilder<QuerySnapshot>(
        streamKey: (badgeCollection, companyUID),
        create: () => FirebaseFirestore.instance
            .collection(badgeCollection)
            .where('companyUID', isEqualTo: companyUID)
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          final count = snapshot.data?.docs.length ?? 0;
          return Badge(
            isLabelVisible: count > 0,
            label: Text(
              '$count',
              style: const TextStyle(fontSize: HrFont.labelSmall, fontWeight: FontWeight.bold),
            ),
            backgroundColor: colorScheme.error,
            textColor: colorScheme.onError,
            child: Icon(
              isSelected ? item.selectedIcon : item.icon,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 22,
            ),
          );
        },
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(HrRadius.card),
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}
