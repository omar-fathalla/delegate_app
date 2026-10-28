import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/marketing/data/services/floor_verification_service.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/models/floor_verification_model.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// الشاشة الرئيسية لمسؤول تسويق الفروع (Branch Marketing Dashboard)
/// تعرض الترحيب بالاسم، وتفاصيل المهام الثلاث اليومية، وكروت الوصول السريع، والملخص الميداني
class MarketingHomeScreen extends StatefulWidget {
  final Delegate delegate;
  final Function(int tabIndex) onNavigateTab;

  const MarketingHomeScreen({
    super.key,
    required this.delegate,
    required this.onNavigateTab,
  });

  @override
  State<MarketingHomeScreen> createState() => _MarketingHomeScreenState();
}

class _MarketingHomeScreenState extends State<MarketingHomeScreen> {
  late final FloorVerificationService _floorService;
  late final BranchPreferenceService _prefService;
  List<String> _favoriteBranches = [];
  List<Map<String, dynamic>> _todayRecords = [];
  Map<String, FloorVerificationItem> _floorVerifications = {};
  bool _isLoadingAttendance = true;

  @override
  void initState() {
    super.initState();
    try {
      _floorService = di.sl<FloorVerificationService>();
      _prefService = di.sl<BranchPreferenceService>();
      _floorService.addListener(_onFloorServiceChanged);
      _loadFloorData();
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _floorService.removeListener(_onFloorServiceChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onFloorServiceChanged() {
    if (!mounted) return;
    setState(() {
      _floorVerifications = _floorService.getLocalVerifications(DateTime.now());
    });
  }

  Future<void> _loadFloorData({bool forceRefresh = false}) async {
    try {
      final favs = _prefService.getFavoriteBranches(widget.delegate.uid);
      if (favs.isNotEmpty) {
        _favoriteBranches = favs;
      } else {
        final active = _prefService.getActiveBranch(widget.delegate.uid);
        _favoriteBranches = (active != null && active.isNotEmpty) ? [active] : [];
      }

      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      // Instant 0ms local read
      _floorVerifications = _floorService.getLocalVerifications(today);

      final prefs = di.sl<SharedPreferences>();
      final cacheKey = 'mkt_today_records_${widget.delegate.uid}_$todayStr';
      if (!forceRefresh) {
        final cached = prefs.getString(cacheKey);
        if (cached != null && cached.isNotEmpty) {
          final decoded = json.decode(cached) as List<dynamic>;
          _todayRecords = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _isLoadingAttendance = false;
          if (mounted) setState(() {});
        }
      }

      if (_favoriteBranches.isEmpty) {
        if (mounted) setState(() => _isLoadingAttendance = false);
        return;
      }

      // Background remote fetch
      final remoteDataSource = di.sl<MarketingRemoteDataSource>();
      final orgId = widget.delegate.organizationUID.isNotEmpty
          ? widget.delegate.organizationUID
          : 'PiioBFgxaHAeuRdjlDgj';

      final res = await remoteDataSource.getTodayAttendanceForBranches(
        branchNames: _favoriteBranches,
        organizationId: orgId,
        date: today,
        onFirstPaint: (partial) {
          final early = <Map<String, dynamic>>[];
          for (final list in partial.values) {
            early.addAll(list);
          }
          if (mounted) {
            setState(() {
              _todayRecords = early;
              _isLoadingAttendance = false;
            });
          }
        },
      );

      final allRecs = <Map<String, dynamic>>[];
      for (final list in res.values) {
        allRecs.addAll(list);
      }

      if (mounted) {
        setState(() {
          _todayRecords = allRecs;
          _isLoadingAttendance = false;
        });
      }

      // Cache minimal records for 0ms next load
      final minimal = allRecs
          .map((r) => {
                'delegateId': r['delegateId'] ?? '',
                'fullName': r['fullName'] ?? '',
                'branchName': r['branchName'] ?? '',
              })
          .toList();
      await prefs.setString(cacheKey, json.encode(minimal));

      // Cloud sync verifications
      final cloudVerifications = await _floorService.fetchCloudVerifications(
        date: today,
        branchNames: _favoriteBranches,
      );
      if (mounted) {
        setState(() {
          _floorVerifications = cloudVerifications;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAttendance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return RefreshIndicator(
      onRefresh: () async {
        await _loadFloorData(forceRefresh: true);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. الكارت الترحيبي والتعريفي الرئيسي مع دليل المهام
            _buildWelcomeDutiesBanner(context, colorScheme, isArabic),

            const SizedBox(height: 16),

            // 1.1 مدخل وصول سريع لتبويب العلامة الخاصة الموحد (Private Label)
            _buildPrivateLabelShortcutCard(context, colorScheme, isArabic),
            const SizedBox(height: 16),

            // 2. عنوان لوحة العمليات والوصول السريع
            Row(
              children: [
                Icon(
                  Icons.dashboard_customize_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  isArabic ? 'لوحة العمليات والوصول السريع' : 'Quick Operations Hub',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 3. شبكة كروت العمليات السريعة (4 كروت)
            _buildQuickOperationsGrid(context, colorScheme, isArabic),

            const SizedBox(height: 20),

            // 4. عنوان ملخص الميداني اليومي
            Row(
              children: [
                Icon(
                  Icons.assignment_turned_in_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  isArabic ? 'ملخص الميداني اليومي' : 'Daily Field Summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // كارت التحقق الميداني بالصالة (اليومي)
            _buildDailyFloorInspectionOverview(context, colorScheme, isArabic),

            const SizedBox(height: 16),

            // 5. نصيحة وتوجيه ميداني
            _buildFieldGuidanceCard(context, colorScheme, isArabic),
          ],
        ),
      ),
    );
  }

  /// 1. الكارت الترحيبي الشامل مع المهام اليومية الثلاث
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
          // رأس الكارت: الترحيب والاسم وشارة الوظيفة
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'أهلاً بك، $displayName' : 'Welcome, $displayName',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // شارة المنظمة
                    if (delegate.organizationName.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.corporate_fare_rounded,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              delegate.organizationName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    // شارة المسمى الوظيفي
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
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
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.roleBranchMarketing,
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
              // صورة الأفاتار الدائرية لمسؤول التسويق
              Builder(
                builder: (context) {
                  String? photoUrl = widget.delegate.personalPhotoUrl ??
                      (widget.delegate.documents
                          .where((d) =>
                              d.documentKey == DocumentKey.personalPhoto &&
                              d.documentURL.isNotEmpty)
                          .firstOrNull
                          ?.documentURL);
                  if (photoUrl == null) {
                    try {
                      photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
                    } catch (_) {}
                  }

                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: AppAvatar(
                      imageUrl: photoUrl,
                      fallbackText: widget.delegate.firstName,
                      radius: 26,
                      backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                      foregroundColor: colorScheme.primary,
                      fallbackIcon: Icons.campaign_rounded,
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.35), height: 1),
          const SizedBox(height: 14),

          // عنوان دليل المهام والمسؤوليات
          Text(
            isArabic
                ? 'دليل المهام والمسؤوليات اليومية لفرعك:'
                : 'Your Daily Branch Responsibilities:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),

          // المهمة 1: المرور اليومي وفحص المناديب
          _buildDutyBullet(
            icon: Icons.directions_walk_rounded,
            title: isArabic
                ? '1. المرور الميداني ومتابعة حضور المناديب:'
                : '1. Daily walk & delegate check-in review:',
            desc: isArabic
                ? 'المرور على أقسام الفرع والتأكد من تواجد مناديب الشركات ومطابقة تسجيل حضورهم الفعلي.'
                : 'Inspect branch aisles, check vendor delegates attendance, and ensure physical presence.',
            colorScheme: colorScheme,
          ),

          const SizedBox(height: 8),

          // المهمة 2: مراجعة وتدقيق أذونات التصوير
          _buildDutyBullet(
            icon: Icons.camera_enhance_rounded,
            title: isArabic
                ? '2. مراجعة وتدقيق أذونات وتصاريح التصوير:'
                : '2. Audit & verify photo permissions:',
            desc: isArabic
                ? 'التحقق من تصاريح التصوير الممنوحة للشركات داخل الفرع واعتمادها قبل بدء أي جلسة تصوير ترويجي.'
                : 'Review, approve, and verify vendor marketing photo permits before capturing displays.',
            colorScheme: colorScheme,
          ),

          const SizedBox(height: 8),

          // المهمة 3: تسجيل وضبط الغرامات والمخالفات
          _buildDutyBullet(
            icon: Icons.gavel_rounded,
            title: isArabic
                ? '3. تسجيل وضبط المخالفات وتطبيق لائحة الجزاءات:'
                : '3. Record violations & apply penalty rules:',
            desc: isArabic
                ? 'رصد التجاوزات الميدانية (عدم الالتزام بالزي، التواجد بدون تصريح، مخالفة التعليمات) وتوثيق الغرامة فورياً.'
                : 'Record field violations on delegates or companies instantly according to official penalty regulations.',
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  /// بطاقة وصول سريعة وأنيقة لتبويب Private Label الموحد الجديد
  Widget _buildPrivateLabelShortcutCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
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
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDutyBullet({
    required IconData icon,
    required String title,
    required String desc,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2. شبكة كروت العمليات السريعة (4 كروت تفاعلية)
  Widget _buildQuickOperationsGrid(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.15,
      children: [
        // كارت 1: الفروع ومتابعة الحضور
        _buildActionCard(
          context: context,
          icon: Icons.storefront_rounded,
          iconColor: colorScheme.primary,
          cardColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderColor: colorScheme.primary.withValues(alpha: 0.25),
          title: isArabic ? 'متابعة الفروع' : 'Branch Attendance',
          subtitle: isArabic
              ? 'حضور وتواجد المناديب'
              : 'Monitor daily attendance',
          onTap: () => widget.onNavigateTab(1),
        ),

        // كارت 2: أذونات التصوير
        _buildActionCard(
          context: context,
          icon: Icons.photo_library_rounded,
          iconColor: colorScheme.tertiary,
          cardColor: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          borderColor: colorScheme.tertiary.withValues(alpha: 0.25),
          title: isArabic ? 'أذونات التصوير' : 'Photo Permissions',
          subtitle: isArabic
              ? 'اعتماد تصاريح الشركات'
              : 'Review & approve permits',
          onTap: () => widget.onNavigateTab(2),
        ),

        // كارت 3: تسجيل الغرامات والمخالفات
        _buildActionCard(
          context: context,
          icon: Icons.gavel_rounded,
          iconColor: colorScheme.error,
          cardColor: colorScheme.errorContainer.withValues(alpha: 0.5),
          borderColor: colorScheme.error.withValues(alpha: 0.25),
          title: isArabic ? 'تسجيل مخالفة' : 'Penalties System',
          subtitle: isArabic
              ? 'تطبيق لائحة الجزاءات'
              : 'Record fines & violations',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider(
                  create: (_) => di.sl<PenaltyBloc>(),
                  child: CompanyPenaltiesSettingsPage(
                    delegate: widget.delegate,
                    showAppBar: true,
                  ),
                ),
              ),
            );
          },
        ),

        // كارت 4: البحث والاستعلام السريع
        _buildActionCard(
          context: context,
          icon: Icons.person_search_rounded,
          iconColor: colorScheme.secondary,
          cardColor: colorScheme.secondaryContainer.withValues(alpha: 0.5),
          borderColor: colorScheme.secondary.withValues(alpha: 0.25),
          title: isArabic ? 'البحث والتحقق' : 'Search & Verify',
          subtitle: isArabic
              ? 'ملفات المناديب والشركات'
              : 'Find delegate or company',
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
      ],
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color cardColor,
    required Color borderColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
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
                      fontSize: 14,
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
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
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

  /// 3. ملخص الميداني اليومي (التحقق الميداني بالصالة)
  Widget _buildDailyFloorInspectionOverview(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    final theme = Theme.of(context);
    final totalCount = _todayRecords.length;
    final verifiedCount = _todayRecords
        .where((r) => _floorVerifications[r['delegateId']]?.isVerified == true)
        .length;
    final missingCount = _todayRecords
        .where((r) => _floorVerifications[r['delegateId']]?.isMissing == true)
        .length;
    final remainingCount = (totalCount - verifiedCount - missingCount).clamp(0, totalCount);
    final percent = totalCount > 0 ? (verifiedCount / totalCount) : 0.0;
    final percentInt = (percent * 100).toInt();
    final isComplete = totalCount > 0 && verifiedCount == totalCount;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          hoverColor: colorScheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          onTap: () => widget.onNavigateTab(1),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // رأس الكارت: الأيقونة + العنوان + النسبة
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: isComplete
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.14)
                            : colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isComplete
                            ? Icons.verified_rounded
                            : Icons.fact_check_rounded,
                        size: 20,
                        color: isComplete
                            ? const Color(0xFF2E7D32)
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isArabic ? 'التحقق الميداني بالصالة' : 'Floor Verification',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            _favoriteBranches.isNotEmpty
                                ? (_favoriteBranches.length == 1
                                    ? (isArabic
                                        ? 'فرع ${_favoriteBranches.first}'
                                        : 'Branch ${_favoriteBranches.first}')
                                    : (isArabic
                                        ? 'عبر ${_favoriteBranches.length} فروع مفضلة'
                                        : 'Across ${_favoriteBranches.length} favorite branches'))
                                : (isArabic
                                    ? 'معدل المرور اليومي على المناديب'
                                    : 'Daily floor check progress'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // نسبة التحقق الميداني
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isComplete
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$percentInt%',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isComplete
                              ? const Color(0xFF2E7D32)
                              : (percentInt == 0
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.primary),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // شريط التقدم المرئي
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 7,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isComplete
                          ? const Color(0xFF2E7D32)
                          : colorScheme.primary,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // سطر الإحصائيات والتفاصيل
                Row(
                  children: [
                    Text(
                      totalCount > 0
                          ? (isArabic
                              ? 'تم المرور على $verifiedCount من $totalCount مندوب'
                              : '$verifiedCount of $totalCount delegates checked')
                          : (_isLoadingAttendance
                              ? (isArabic ? 'جاري تحميل الحضور...' : 'Loading attendance...')
                              : (isArabic ? 'لا يوجد حضور مسجل اليوم' : 'No attendance recorded today')),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (totalCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: remainingCount > 0
                              ? colorScheme.secondaryContainer.withValues(alpha: 0.6)
                              : const Color(0xFF2E7D32).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          remainingCount > 0
                              ? (isArabic ? 'المتبقي: $remainingCount' : '$remainingCount remaining')
                              : (isArabic ? 'اكتمل المرور' : 'All checked'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: remainingCount > 0
                                ? colorScheme.onSecondaryContainer
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // زر الانتقال لصفحة الفروع لبدء/استكمال المرور
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.tonal(
                    onPressed: () => widget.onNavigateTab(1),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isArabic ? 'متابعة المرور اليومي للمناديب' : 'Daily Delegates Tour',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 4. نصيحة وتوجيه ميداني
  Widget _buildFieldGuidanceCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_rounded,
            color: colorScheme.secondary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isArabic
                  ? 'تنبيه ميداني: يرجى مراجعة وتدقيق بطاقة المندوب وتاريخ سريان تصريح التصوير قبل السماح بأي تصوير ترويجي داخل الفرع.'
                  : 'Field Reminder: Please inspect the delegate ID and permission expiry date before permitting promotional captures.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
