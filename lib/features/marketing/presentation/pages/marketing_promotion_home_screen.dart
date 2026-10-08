import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_screen.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_review_screen.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_report_screen.dart';
import 'package:delegate_app/injection_container.dart';

/// الشاشة الرئيسية الترحيبية لمسؤول تسويق العروض الترويجية (Marketing Promotion Home)
/// تعرض الترحيب بالاسم، ودليل المهام والمسؤوليات، ولوحة المؤشرات المفلترة بالأقسام المثبتة، والإرشادات التشغيلية
class MarketingPromotionHomeScreen extends StatefulWidget {
  final Delegate delegate;
  final Function(int tabIndex) onNavigateTab;

  const MarketingPromotionHomeScreen({
    super.key,
    required this.delegate,
    required this.onNavigateTab,
  });

  @override
  State<MarketingPromotionHomeScreen> createState() => _MarketingPromotionHomeScreenState();
}

class _MarketingPromotionHomeScreenState extends State<MarketingPromotionHomeScreen> {
  Set<String> _pinnedDepartments = {};
  StreamSubscription<PrivateLabelPermissions?>? _permissionsSubscription;
  PrivateLabelPermissions? _permissions;

  bool get _isSuperAdmin => widget.delegate.role == UserRole.superAdmin;
  bool get _canCapture => _isSuperAdmin || (_permissions?.canCapture ?? false);
  bool get _canViewReports => _isSuperAdmin || (_permissions?.canViewReports ?? false);
  bool get _canReviewAudit => _isSuperAdmin || (_permissions?.canReviewAudit ?? false);

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
      if (mounted) {
        setState(() {
          _pinnedDepartments = list != null ? list.toSet() : {};
        });
      }
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

            // 1.1 مدخل تدقيق البرايفت ليبل
            if (_canReviewAudit) ...[
              _buildPrivateLabelAuditEntry(context, colorScheme),
              const SizedBox(height: 10),
            ],

            // 1.2 مدخل تقارير البرايفت ليبل (نسب الإنجاز الشهرية للفروع والمسوقين)
            if (_canViewReports) ...[
              _buildPrivateLabelReportEntry(context, colorScheme),
              const SizedBox(height: 10),
            ],

            // 1.3 مدخل التوثيق الميداني للبرايفت ليبل (تصوير المنتجات وبطاقات الأسعار)
            if (_canCapture) ...[
              _buildPrivateLabelCaptureEntry(context, colorScheme),
              const SizedBox(height: 10),
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

  /// مدخل شاشة تدقيق البرايفت ليبل (صور المنتج + بطاقة السعر من الفروع)
  Widget _buildPrivateLabelAuditEntry(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrivateLabelReviewScreen(delegate: widget.delegate),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.fact_check_rounded, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Private Label Audit',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'مراجعة صور المنتجات وبطاقات الأسعار من الفروع وفلترة مخالفات الأسعار',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// مدخل شاشة تقارير البرايفت ليبل (نسب الإنجاز الشهرية وترتيب الفروع والمسوقين)
  Widget _buildPrivateLabelReportEntry(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrivateLabelReportScreen(delegate: widget.delegate),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.analytics_rounded, color: colorScheme.onSecondaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Private Label Report',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'مؤشرات ونسب إنجاز الفروع والمسوقين وترتيب الأداء الشهري',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// مدخل شاشة التوثيق الميداني للبرايفت ليبل (تصوير المنتجات وبطاقات الأسعار)
  Widget _buildPrivateLabelCaptureEntry(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrivateLabelScreen(delegate: widget.delegate),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.camera_alt_rounded, color: colorScheme.onTertiaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Private Label Capture',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'التوثيق الميداني اليومي للمنتجات وبطاقات الأسعار في الفروع',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorScheme.onSurfaceVariant),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  color: colorScheme.primary,
                  size: 28,
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
            title: isArabic
                ? 'التواصل مع تسويق الفروع عبر المهام'
                : 'Branch Marketing Coordination',
            subtitle: isArabic
                ? 'إرسال وتوجيه المهام الميدانية لمسؤولي الفروع لمتابعة تجهيز العروض والالتزام بالمعايير.'
                : 'Send & monitor operational tasks to branch marketing teams for display readiness.',
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collectionGroup('permissions').snapshots(),
      builder: (context, permissionsSnapshot) {
        int pendingCount = 0;
        int activeCount = 0;

        if (permissionsSnapshot.hasData) {
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

          for (final doc in permissionsSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
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
        }

        return Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: isArabic ? 'طلبات بانتظار الاعتماد' : 'Pending Requests',
                value: permissionsSnapshot.connectionState == ConnectionState.waiting
                    ? '...'
                    : '$pendingCount',
                icon: Icons.pending_actions_rounded,
                color: colorScheme.tertiary,
                onTap: () => widget.onNavigateTab(1), // الانتقال المباشر لتبويب أذونات التصوير
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: isArabic ? 'أذونات نشطة وسارية' : 'Active Permissions',
                value: permissionsSnapshot.connectionState == ConnectionState.waiting
                    ? '...'
                    : '$activeCount',
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
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
                    color: Theme.of(context).colorScheme.outline,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
