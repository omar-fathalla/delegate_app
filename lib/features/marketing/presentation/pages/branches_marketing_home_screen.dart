import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/presentation/pages/create_task_screen.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/features/notifications/presentation/pages/send_notification_screen.dart';

/// الشاشة الرئيسية لمدير تسويق الفروع (Branches Marketing Manager Home Screen)
/// تعرض الاسم بوضوح والمهام التنفيذية الرئيسية:
/// 1. الموافقة على أذونات التصوير
/// 2. متابعة تسويق الفروع
/// 3. تعديل وإدارة مهام التسويق
class BranchesMarketingHomeScreen extends StatefulWidget {
  final Delegate delegate;
  final Function(int tabIndex) onNavigateTab;

  const BranchesMarketingHomeScreen({
    super.key,
    required this.delegate,
    required this.onNavigateTab,
  });

  @override
  State<BranchesMarketingHomeScreen> createState() =>
      _BranchesMarketingHomeScreenState();
}

class _BranchesMarketingHomeScreenState
    extends State<BranchesMarketingHomeScreen> {
  int _cachedPendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCachedMetrics();
  }

  Future<void> _loadCachedMetrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orgId = widget.delegate.organizationUID;
      final cachedPending =
          prefs.getInt('photo_permissions_pending_count_$orgId') ?? 0;
      if (mounted) {
        setState(() {
          _cachedPendingCount = cachedPending;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCachedPendingCount(int pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orgId = widget.delegate.organizationUID;
      await prefs.setInt('photo_permissions_pending_count_$orgId', pending);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return RefreshIndicator(
      onRefresh: () async {
        await _loadCachedMetrics();
        setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. كارت الترحيب والتعريف بمدير تسويق الفروع
            _buildWelcomeManagerHeader(context, colorScheme, isArabic),

            const SizedBox(height: 18),

            // 2. شريط النبض والمؤشرات الميدانية اللحظية
            _buildLiveMetricsBar(context, colorScheme, isArabic),

            const SizedBox(height: 22),

            // 3. قسم المهام والمسؤوليات الرئيسية للمدير
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.assignment_turned_in_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isArabic
                      ? 'المهام والمسؤوليات التنفيذية'
                      : 'Executive Responsibilities',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 4. كروت المهام الأربعة الرئيسية
            _buildCoreResponsibilitiesList(context, colorScheme, isArabic),

            const SizedBox(height: 22),

            // 5. أدوات الوصول السريع والعمليات الميدانية
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.grid_view_rounded,
                    color: colorScheme.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isArabic ? 'الوصول السريع للأدوات' : 'Quick Access Hub',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 6. شبكة الأدوات الميدانية السريعة
            _buildQuickToolsGrid(context, colorScheme, isArabic),

            const SizedBox(height: 18),

            // 7. بطاقة التوجيهات والملاحظات التنفيذية
            _buildExecutiveGuidanceCard(context, colorScheme, isArabic),
          ],
        ),
      ),
    );
  }

  /// 1. كارت الترحيب والتعريف بمدير تسويق الفروع
  Widget _buildWelcomeManagerHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    final delegate = widget.delegate;
    final displayName = delegate.fullName.isNotEmpty
        ? delegate.fullName
        : (delegate.firstName.isNotEmpty ? delegate.firstName : 'مدير التسويق');

    final now = DateTime.now();
    final dateFormatted = isArabic
        ? DateFormat('EEEE، d MMMM y', 'ar').format(now)
        : DateFormat('EEEE, MMMM d, y').format(now);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الأيقونة والصورة الشخصية
              Hero(
                tag: 'header_avatar_${delegate.uid}',
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: AppAvatar(
                    imageUrl: delegate.personalPhotoUrl,
                    fallbackText: delegate.firstName,
                    radius: 26,
                    fallbackIcon: Icons.campaign_rounded,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                    foregroundColor: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // الاسم والمنصب
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'مرحباً بك،' : 'Welcome,',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // شارة المسمى الوظيفي
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 13,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isArabic
                                ? 'مدير تسويق الفروع'
                                : 'Branches Marketing Manager',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.35), height: 1),
          const SizedBox(height: 12),

          // شريط التاريخ والمنظمة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // التاريخ اليومي
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dateFormatted,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // اسم المنظمة إن وجد
              if (delegate.organizationName.isNotEmpty)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.corporate_fare_rounded,
                        size: 13,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          delegate.organizationName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 2. شريط النبض والمؤشرات الميدانية اللحظية
  Widget _buildLiveMetricsBar(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collectionGroup('photo_permissions')
          .where('status', isEqualTo: 'pending')
          .limit(100)
          .streamResilient(includeMetadataChanges: true),
      builder: (context, snapshot) {
        int pendingCount = _cachedPendingCount;
        if (snapshot.hasData) {
          final seenKeys = <String>{};
          final orgUID = widget.delegate.organizationUID;
          int count = 0;
          for (final doc in snapshot.data!.docs) {
            final data = doc.data();
            final docOrg = (data['organizationUID'] ?? '').toString();
            if (orgUID.isNotEmpty && docOrg.isNotEmpty && docOrg != orgUID) {
              continue;
            }
            final compId = (data['companyUID'] ?? '').toString();
            if (seenKeys.add('${compId}_${doc.id}')) {
              count++;
            }
          }
          pendingCount = count;
          if (pendingCount != _cachedPendingCount) {
            _cachedPendingCount = pendingCount;
            _saveCachedPendingCount(pendingCount);
          }
        }

        return Row(
          children: [
            // مؤشر 1: أذونات بانتظار الاعتماد
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => widget.onNavigateTab(1),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: pendingCount > 0
                        ? colorScheme.tertiaryContainer.withValues(alpha: 0.35)
                        : colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: pendingCount > 0
                          ? colorScheme.tertiary.withValues(alpha: 0.5)
                          : colorScheme.outlineVariant,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: pendingCount > 0
                              ? colorScheme.tertiaryContainer
                              : colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.pending_actions_rounded,
                          color: pendingCount > 0
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$pendingCount',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: pendingCount > 0
                                    ? colorScheme.tertiary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              isArabic ? 'بانتظار الاعتماد' : 'Pending Approvals',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // مؤشر 2: متابعة المهام
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => widget.onNavigateTab(2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.task_alt_rounded,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isArabic ? 'المهام' : 'Tasks',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              isArabic ? 'متابعة وإنجاز' : 'Manage & Track',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 3. كروت المهام الأربعة الرئيسية المطلوبة لمدير تسويق الفروع
  Widget _buildCoreResponsibilitiesList(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Column(
      children: [
        // ── المهمة 1: الموافقة على أذونات التصوير ──
        _buildExecutiveDutyCard(
          context: context,
          icon: Icons.verified_user_rounded,
          iconColor: colorScheme.tertiary,
          badgeText: isArabic ? 'مهمة أساسية' : 'Core Duty',
          title: isArabic
              ? 'الموافقة على أذونات التصوير'
              : 'Approve Photo Permissions',
          description: isArabic
              ? 'مراجعة طلبات تصاريح التصوير المرفوعة لشركات المعروضات واعتمادها أو رفضها فورياً مع تتبع سريانها.'
              : 'Review and approve/reject marketing photo permissions for vendor delegates with live validity tracking.',
          actionButtonText: isArabic ? 'اعتماد الأذونات' : 'Review & Approve',
          onTap: () => widget.onNavigateTab(1),
        ),

        const SizedBox(height: 12),

        // ── المهمة 2: متابعة تسويق الفروع ──
        _buildExecutiveDutyCard(
          context: context,
          icon: Icons.storefront_rounded,
          iconColor: colorScheme.primary,
          badgeText: isArabic ? 'ميداني' : 'Field Operations',
          title: isArabic
              ? 'متابعة تسويق الفروع'
              : 'Branch Marketing Follow-up',
          description: isArabic
              ? 'متابعة الفروع والعروض الترويجية، فحص تواجد مناديب الشركات، ومطابقة تسجيل الحضور الميداني بالفرع.'
              : 'Monitor branch promotion activities, vendor delegates presence, and verify on-ground attendance.',
          actionButtonText: isArabic ? 'فتح متابعة الفروع' : 'Open Branches Hub',
          onTap: () => widget.onNavigateTab(2),
        ),

        const SizedBox(height: 12),

        // ── المهمة 3: تعديل وإدارة مهام التسويق ──
        _buildExecutiveDutyCard(
          context: context,
          icon: Icons.edit_calendar_rounded,
          iconColor: colorScheme.secondary,
          badgeText: isArabic ? 'إدارة وتوجيه' : 'Task Dispatch',
          title: isArabic
              ? 'تعديل وإدارة مهام التسويق'
              : 'Manage & Edit Marketing Tasks',
          description: isArabic
              ? 'إسناد وتعديل المهام الميدانية لمناديب الفروع، متابعة سير التنفيذ، وإضافة مهام تسويقية جديدة.'
              : 'Dispatch and edit field tasks for branch delegates, track progress, and create new campaigns.',
          actionButtonText: isArabic ? 'استعراض المهام' : 'View Tasks',
          secondaryButtonText: isArabic ? '+ مهمة جديدة' : '+ New Task',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminTasksScreen(
                  adminDelegate: widget.delegate,
                ),
              ),
            );
          },
          onSecondaryTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CreateTaskScreen(
                  adminDelegate: widget.delegate,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// كارت مهمة تنفيذية مخصص بتصميم أنيق وتفاعلي
  Widget _buildExecutiveDutyCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String badgeText,
    required String title,
    required String description,
    required String actionButtonText,
    required VoidCallback onTap,
    String? secondaryButtonText,
    VoidCallback? onSecondaryTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الرأس: الأيقونة + شارة الوظيفة
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // الوصف
          Text(
            description,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 14),

          // أزرار الإجراءات
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(
                    actionButtonText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: iconColor.withValues(alpha: 0.12),
                    foregroundColor: iconColor,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (secondaryButtonText != null && onSecondaryTap != null) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onSecondaryTap,
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text(
                    secondaryButtonText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 4. شبكة الأدوات الميدانية والوصول السريع
  Widget _buildQuickToolsGrid(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.22,
      children: [
        // أداة 1: البحث والاستعلام
        _buildToolItemCard(
          context: context,
          icon: Icons.person_search_rounded,
          iconColor: colorScheme.primary,
          title: isArabic ? 'الاستعلامات والبحث' : 'Search & Verify',
          subtitle: isArabic ? 'كود الشركة أو هاتف المندوب' : 'Find company/delegate',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MarketingSearchScreen(
                  organizationUID: widget.delegate.organizationUID,
                ),
              ),
            );
          },
        ),

        // أداة 2: لائحة المخالفات والغرامات
        _buildToolItemCard(
          context: context,
          icon: Icons.gavel_rounded,
          iconColor: colorScheme.error,
          title: isArabic ? 'لائحة الغرامات' : 'Penalties System',
          subtitle: isArabic ? 'رصد وتطبيق الجزاءات' : 'View & record fines',
          onTap: () => widget.onNavigateTab(3),
        ),

        // أداة 3: إرسال إشعار للمناديب
        _buildToolItemCard(
          context: context,
          icon: Icons.campaign_rounded,
          iconColor: colorScheme.tertiary,
          title: isArabic ? 'إرسال إشعار' : 'Broadcast Alert',
          subtitle: isArabic ? 'تنبيه فوري للمناديب' : 'Push notifications',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SendNotificationScreen(
                  senderDelegate: widget.delegate,
                ),
              ),
            );
          },
        ),

        // أداة 4: إدارة المهام
        _buildToolItemCard(
          context: context,
          icon: Icons.task_alt_rounded,
          iconColor: colorScheme.secondary,
          title: isArabic ? 'إدارة المهام' : 'Tasks',
          subtitle: isArabic ? 'متابعة وتكليف' : 'Dispatch & track',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminTasksScreen(
                  adminDelegate: widget.delegate,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildToolItemCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: colorScheme.outline,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 5. بطاقة التوجيهات والملاحظات التنفيذية
  Widget _buildExecutiveGuidanceCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: colorScheme.secondary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isArabic
                  ? 'ملاحظة تنظيمية: يرجى اعتماد أذونات التصوير والتأكد من تواجد مناديب الشركات بالزي المعتمد داخل الفرع قبل بدء أي حملة ترويجية لضمان الامتثال للائحة.'
                  : 'Notice: Please ensure photo permissions are approved and delegates are in full uniform before starting in-branch promotions.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
