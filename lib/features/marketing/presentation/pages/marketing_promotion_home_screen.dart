import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/injection_container.dart';

/// الشاشة الرئيسية الترحيبية لمسؤول تسويق العروض الترويجية (Marketing Promotion Home)
/// تعرض الترحيب بالاسم، ودليل المهام والمسؤوليات، ولوحة المؤشرات المفلترة بالأقسام المثبتة، والإرشادات التشغيلية
class MarketingPromotionHomeScreen extends StatefulWidget {
  final Delegate delegate;
  final Function(int tabIndex) onNavigateTab;
  final FirebaseFirestore? firestore;

  const MarketingPromotionHomeScreen({
    super.key,
    required this.delegate,
    required this.onNavigateTab,
    this.firestore,
  });

  @override
  State<MarketingPromotionHomeScreen> createState() => _MarketingPromotionHomeScreenState();
}

class _MarketingPromotionHomeScreenState extends State<MarketingPromotionHomeScreen> {
  Set<String> _pinnedDepartments = {};
  int _cachedPendingCount = 0;
  int _cachedActiveCount = 0;
  StreamSubscription<PrivateLabelPermissions?>? _permissionsSubscription;
  PrivateLabelPermissions? _permissions;

  bool get _isSuperAdmin => widget.delegate.role == UserRole.superAdmin;
  bool get _canCapture => _isSuperAdmin || (_permissions?.canCapture ?? false);
  bool get _canViewReports => _isSuperAdmin || (_permissions?.canViewReports ?? false);
  bool get _canReviewAudit => _isSuperAdmin || (_permissions?.canReviewAudit ?? false);
  bool get _hasPrivateLabelAccess =>
      _isSuperAdmin || _canCapture || _canViewReports || _canReviewAudit;

  @override
  void initState() {
    super.initState();
    _loadPinnedDepartments();
    _listenToPermissions();
  }

  void _listenToPermissions() {
    _permissionsSubscription = sl<PrivateLabelPermissionsRemoteDataSource>()
        .streamUserPermissions(widget.delegate.uid)
        .listen((p) {
      if (mounted) {
        setState(() => _permissions = p);
      }
    });
  }

  @override
  void dispose() {
    _permissionsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPinnedDepartments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'pinned_photo_departments_${widget.delegate.uid}';
      final list = prefs.getStringList(key);
      final orgId = widget.delegate.organizationUID;
      final cachedPending = prefs.getInt('photo_permissions_pending_count_$orgId') ?? 0;
      final cachedActive = prefs.getInt('photo_permissions_active_count_$orgId') ?? 0;
      if (mounted) {
        setState(() {
          _pinnedDepartments = list != null ? list.toSet() : {};
          _cachedPendingCount = cachedPending;
          _cachedActiveCount = cachedActive;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCachedPulseCounts(int pending, int active) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orgId = widget.delegate.organizationUID;
      await prefs.setInt('photo_permissions_pending_count_$orgId', pending);
      await prefs.setInt('photo_permissions_active_count_$orgId', active);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return RefreshIndicator(
      onRefresh: () async {
        await _loadPinnedDepartments();
        setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. الكارت الترحيبي والتعريفي الرئيسي مع دليل المهام والمسؤوليات
            _buildWelcomeDutiesBanner(context, colorScheme, isArabic),

            const SizedBox(height: 16),

            // 1.1 مدخل وصول سريع لتبويب العلامة الخاصة الموحد (Private Label)
            if (_hasPrivateLabelAccess) ...[
              _buildPrivateLabelShortcutCard(context, colorScheme, isArabic),
              const SizedBox(height: 16),
            ],

            // 2. النبض اللحظي والمؤشرات (طلبات الانتظار والأذونات السارية)
            Row(
              children: [
                Icon(
                  Icons.analytics_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic ? 'المؤشرات والنبض اللحظي' : 'Live Operations Pulse',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (_pinnedDepartments.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.push_pin_rounded, size: 12, color: colorScheme.tertiary),
                        const SizedBox(width: 4),
                        Text(
                          'أقسام مثبتة (${_pinnedDepartments.length})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // 3. كروت الإحصائيات الحية (2 كارت فقط: طلبات بانتظار الاعتماد + أذونات نشطة وسارية مفلترة بالأقسام المثبتة)
            _buildLivePulseCards(context, colorScheme, isArabic),

            const SizedBox(height: 20),

            // 4. دليل الإرشادات والتعليمات وسير العمل الميداني
            _buildWorkGuidanceCard(context, colorScheme, isArabic),
          ],
        ),
      ),
    );
  }

  /// بطاقة وصول سريعة وأنيقة لتبويب Private Label الموحد الجديد
  Widget _buildPrivateLabelShortcutCard(BuildContext context, ColorScheme colorScheme, bool isArabic) {
    final theme = Theme.of(context);
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        onTap: () => widget.onNavigateTab(3), // الانتقال لتبويب Private Label الموحد
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.sell_rounded, size: 20, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isArabic ? 'مركز العلامة الخاصة' : 'Private Label Hub',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Private Label',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic
                          ? 'كافة أدوات التوثيق الميداني والتدقيق والتقارير في مكان واحد'
                          : 'All capture, audit, and report tools unified in one tab',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isArabic ? 'فتح' : 'Open',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 11, color: colorScheme.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 1. الكارت الترحيبي الشامل مع المهام والمسؤوليات الرئيسية
  Widget _buildWelcomeDutiesBanner(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;
    final displayName = delegate.firstName.isNotEmpty
        ? delegate.firstName
        : delegate.fullName;

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
          // رأس الكارت الترحيبي
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'مرحباً بك، $displayName' : 'Welcome, $displayName',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isArabic
                            ? 'مسؤول تسويق العروض الترويجية'
                            : 'Marketing Promotion Manager',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.35), height: 1),
          const SizedBox(height: 14),

          // المهام والمسؤوليات الأساسية لليوزر
          Text(
            isArabic ? 'المهام والمسؤوليات التشغيلية:' : 'Core Responsibilities:',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          // 1. مراجعة واعتماد أذونات التصوير
          _buildDutyItem(
            icon: Icons.verified_user_rounded,
            title: isArabic
                ? 'مراجعة واعتماد أذونات التصوير'
                : 'Approve Photo Permissions',
            subtitle: isArabic
                ? 'فحص واعتماد طلبات تصوير العروض المقدمة من الشركات مع تحديد الأقسام والمدد الزمنية.'
                : 'Review & approve company photo permission requests with departments & dates.',
            colorScheme: colorScheme,
          ),

          const SizedBox(height: 8),

          // 2. التواصل والتنسيق مع مسؤولي تسويق الفروع عبر المهام
          _buildDutyItem(
            icon: Icons.task_alt_rounded,
            title: l10n.branchMarketingCoordination,
            subtitle: isArabic
                ? 'إرسال وتوجيه المهام الميدانية لمسؤولي الفروع لمتابعة تجهيز العروض والالتزام بالمعايير.'
                : 'Send & monitor operational tasks to branch marketing specialists for display readiness.',
            colorScheme: colorScheme,
          ),

          const SizedBox(height: 8),

          // 3. متابعة وتوثيق تقارير الصور الميدانية
          _buildDutyItem(
            icon: Icons.photo_camera_rounded,
            title: isArabic
                ? 'متابعة تقارير الصور الميدانية'
                : 'Audit Field Captured Photos',
            subtitle: isArabic
                ? 'الاطلاع على الصور المرفوعة ميدانياً من المناديب داخل الفروع المعتمدة والتأكد من صحتها.'
                : 'Review uploaded store photos from delegates across approved branches.',
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildDutyItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: colorScheme.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2. كروت النبض اللحظي والإحصائيات الحية (2 كارت فقط: طلبات بانتظار الاعتماد + أذونات نشطة وسارية)
  Widget _buildLivePulseCards(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // TAS-73: scoped to the user's company, or its organization when it
      // has none, so the rules can prove the list. Counted on the client.
      stream: photoPermissionsTenantQuery(
        widget.firestore ?? FirebaseFirestore.instance,
        companyUID: widget.delegate.companyUID,
        organizationUID: widget.delegate.organizationUID,
      ).streamResilient(includeMetadataChanges: true),
      builder: (context, permissionsSnapshot) {
        int pendingCount = _cachedPendingCount;
        int activeCount = _cachedActiveCount;

        if (permissionsSnapshot.hasData) {
          pendingCount = 0;
          activeCount = 0;
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
          final seenKeys = <String>{};
          final orgUID = widget.delegate.organizationUID;

          for (final doc in permissionsSnapshot.data!.docs) {
            final data = doc.data();
            final docOrg = (data['organizationUID'] ?? '').toString();
            if (orgUID.isNotEmpty && docOrg.isNotEmpty && docOrg != orgUID) {
              continue;
            }
            final compId = (data['companyUID'] ?? '').toString();
            if (!seenKeys.add('${compId}_${doc.id}')) {
              continue;
            }

            final status = (data['status'] ?? '').toString().toLowerCase();
            final isEnabled = data['isSupervisorEnabled'] ?? true;
            final startDate = (data['startDate'] as Timestamp?)?.toDate();
            final endDate = (data['endDate'] as Timestamp?)?.toDate();
            final dept = data['department'] as String?;

            // تطبيق فلترة الأقسام المثبتة إذا كانت مفعلة لدى المستخدم
            if (_pinnedDepartments.isNotEmpty) {
              if (dept == null || !_pinnedDepartments.contains(dept)) {
                continue; // تجاهل أي إذن خارج الأقسام المثبتة
              }
            }

            if (status == 'pending') {
              pendingCount++;
            } else if (status == 'approved' && isEnabled) {
              if (startDate != null && endDate != null) {
                if (!startDate.isAfter(todayEnd) && !endDate.isBefore(todayStart)) {
                  activeCount++;
                }
              } else {
                activeCount++;
              }
            }
          }

          if (pendingCount != _cachedPendingCount || activeCount != _cachedActiveCount) {
            _cachedPendingCount = pendingCount;
            _cachedActiveCount = activeCount;
            _saveCachedPulseCounts(pendingCount, activeCount);
          }
        }

        return Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: isArabic ? 'طلبات بانتظار الاعتماد' : 'Pending Requests',
                value: '$pendingCount',
                icon: Icons.pending_actions_rounded,
                color: colorScheme.tertiary,
                onTap: () => widget.onNavigateTab(1), // الانتقال المباشر لتبويب أذونات التصوير
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: isArabic ? 'أذونات نشطة وسارية' : 'Active Permissions',
                value: '$activeCount',
                icon: Icons.verified_rounded,
                color: colorScheme.primary,
                onTap: () => widget.onNavigateTab(1), // الانتقال المباشر لتبويب أذونات التصوير
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: colorScheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  /// 3. كارت الإرشادات وسير العمل الميداني
  Widget _buildWorkGuidanceCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: colorScheme.tertiary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                isArabic ? 'إرشادات تشغيلية للمسؤول' : 'Operational Best Practices',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildGuidanceBullet(
            colorScheme,
            isArabic
                ? 'تأكد من اختيار وتثبيت الأقسام التي تتابعها من شريط الفلترة لظهور الإشعارات والطلبات الخاصة بك فوراً.'
                : 'Pin your assigned departments to filter relevant photo requests instantly.',
          ),
          const SizedBox(height: 6),
          _buildGuidanceBullet(
            colorScheme,
            isArabic
                ? 'استخدم أيقونة الاتصال أو الواتساب بجانب زر الحذف للتواصل السريع مع مشرف الشركة عند الحاجة لتعديل الفروع أو المدة.'
                : 'Use the supervisor contact icon next to delete for fast phone & WhatsApp adjustments.',
          ),
          const SizedBox(height: 6),
          _buildGuidanceBullet(
            colorScheme,
            isArabic
                ? 'أرسل مهام واضحة لمسؤولي تسويق الفروع مع تحديد الفرع وتفاصيل العرض الترويجي المطلوب تصويره ومتابعته.'
                : 'Assign precise tasks to branch marketing specialists with store locations & requirements.',
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceBullet(ColorScheme colorScheme, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 6, color: colorScheme.outline),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
