import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart' hide Bidi, TextDirection;
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/pull_to_refresh.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
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
        _favoriteBranches = (active != null && active.isNotEmpty)
            ? [active]
            : [];
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
          _todayRecords = decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
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
          .map(
            (r) => {
              'delegateId': r['delegateId'] ?? '',
              'fullName': r['fullName'] ?? '',
              'branchName': r['branchName'] ?? '',
            },
          )
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
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    // TAS-392: same page skeleton as the delegate home (round 2): one hero,
    // section titles, kit cards (Card.filled + primary icons), kit refresh.
    return PullToRefresh(
      onRefresh: () => _loadFloorData(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(
          TashilSpacing.lg,
          TashilSpacing.md,
          TashilSpacing.lg,
          TashilSpacing.xxl,
        ),
        children: [
          _buildWelcomeHeroCard(context, isArabic),
          const SizedBox(height: TashilSpacing.lg),
          _buildSectionTitle(context, isArabic ? 'ملخص اليوم' : 'Today'),
          _buildDailyFloorInspectionOverview(context, isArabic),
          const SizedBox(height: TashilSpacing.lg),
          _buildSectionTitle(
            context,
            isArabic ? 'الوصول السريع' : 'Quick access',
          ),
          _buildQuickOperations(context, isArabic),
          const SizedBox(height: TashilSpacing.lg),
          _buildDutiesCard(context, isArabic),
          const SizedBox(height: TashilSpacing.sm),
          _buildFieldGuidanceCard(context, isArabic),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: TashilSpacing.xs,
        bottom: TashilSpacing.sm,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Color _heroOn(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onPrimary;
  }

  /// Hero card: greeting on one line, then the role and the chain as icon +
  /// text labels (read-only values are not chips, TAS-384).
  Widget _buildWelcomeHeroCard(BuildContext context, bool isArabic) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final delegate = widget.delegate;
    final displayName = delegate.firstName.isNotEmpty
        ? delegate.firstName
        : delegate.fullName;
    final on = _heroOn(context);
    final isDark = theme.brightness == Brightness.dark;

    String? photoUrl =
        delegate.personalPhotoUrl ??
        (delegate.documents
            .where(
              (d) =>
                  d.documentKey == DocumentKey.personalPhoto &&
                  d.displayUrl.isNotEmpty,
            )
            .firstOrNull
            ?.displayUrl);
    if (photoUrl == null) {
      try {
        photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
      } catch (_) {}
    }

    Widget label(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: on),
        const SizedBox(width: TashilSpacing.xs),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: on),
          ),
        ),
      ],
    );

    return Container(
      key: const Key('marketing_home_hero'),
      padding: const EdgeInsets.all(TashilSpacing.xl),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.primaryContainer : colorScheme.primary,
        borderRadius: BorderRadius.circular(TashilRadius.extraLarge),
      ),
      child: Row(
        children: [
          AppAvatar(
            imageUrl: photoUrl,
            fallbackText: delegate.firstName,
            radius: 26,
            backgroundColor: isDark
                ? colorScheme.primary
                : colorScheme.primaryContainer,
            foregroundColor: isDark
                ? colorScheme.onPrimary
                : colorScheme.onPrimaryContainer,
            fallbackIcon: Icons.campaign_rounded,
          ),
          const SizedBox(width: TashilSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'أهلاً بك، $displayName' : 'Welcome, $displayName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: on,
                  ),
                ),
                const SizedBox(height: TashilSpacing.sm),
                Wrap(
                  spacing: TashilSpacing.lg,
                  runSpacing: TashilSpacing.xs,
                  children: [
                    label(Icons.storefront_rounded, l10n.roleBranchMarketing),
                    if (delegate.organizationName.isNotEmpty)
                      label(
                        Icons.corporate_fare_rounded,
                        delegate.organizationName,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Daily duties: collapsed by default so the day's numbers come first.
  Widget _buildDutiesCard(BuildContext context, bool isArabic) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duties = <(IconData, String, String)>[
      (
        Icons.directions_walk_rounded,
        isArabic
            ? 'المرور الميداني ومتابعة حضور المناديب'
            : 'Daily walk & delegate check-in review',
        isArabic
            ? 'المرور على أقسام الفرع والتأكد من تواجد مناديب الشركات ومطابقة تسجيل حضورهم الفعلي.'
            : 'Inspect branch aisles, check vendor delegates attendance, and ensure physical presence.',
      ),
      (
        Icons.camera_enhance_rounded,
        isArabic
            ? 'مراجعة أذونات وتصاريح التصوير'
            : 'Audit & verify photo permissions',
        isArabic
            ? 'التحقق من تصاريح التصوير الممنوحة للشركات داخل الفرع قبل بدء أي جلسة تصوير ترويجي.'
            : 'Review vendor marketing photo permits before capturing displays.',
      ),
      (
        Icons.gavel_rounded,
        isArabic
            ? 'تسجيل المخالفات وتطبيق لائحة الجزاءات'
            : 'Record violations & apply penalty rules',
        isArabic
            ? 'رصد التجاوزات الميدانية (الزي، التواجد بدون تصريح، مخالفة التعليمات) وتوثيقها فوراً.'
            : 'Record field violations instantly according to the official penalty rules.',
      ),
    ];

    return Card.filled(
      key: const Key('marketing_home_duties'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: _primaryIcon(context, Icons.checklist_rounded),
        title: Text(
          isArabic ? 'دليل المهام اليومية' : 'Daily duties',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          isArabic ? '3 مهام لفرعك كل يوم' : '3 duties for your branch',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(
          TashilSpacing.lg,
          0,
          TashilSpacing.lg,
          TashilSpacing.md,
        ),
        children: [
          for (final (icon, title, desc) in duties)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: colorScheme.primary),
              title: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                desc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Icon in a rounded square on a surface card: primary + onPrimary (TAS-384).
  Widget _primaryIcon(BuildContext context, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(TashilRadius.medium),
      ),
      child: Icon(icon, size: 22, color: colorScheme.onPrimary),
    );
  }

  /// Quick access: one card style and one icon colour for every destination
  /// (no per-card tertiary / error tints).
  Widget _buildQuickOperations(BuildContext context, bool isArabic) {
    void openPenalties() {
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
    }

    void openSearch() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MarketingSearchScreen(
            organizationUID: widget.delegate.organizationUID,
          ),
        ),
      );
    }

    final items = <(Key, IconData, String, String, VoidCallback)>[
      (
        const Key('marketing_quick_branches'),
        Icons.storefront_rounded,
        isArabic ? 'متابعة الفروع' : 'Branches',
        isArabic ? 'حضور المناديب اليوم' : 'Today\'s attendance',
        () => widget.onNavigateTab(1),
      ),
      (
        const Key('marketing_quick_permissions'),
        Icons.photo_library_rounded,
        isArabic ? 'أذونات التصوير' : 'Photo permissions',
        isArabic ? 'تصاريح الشركات' : 'Company permits',
        () => widget.onNavigateTab(2),
      ),
      (
        const Key('marketing_quick_penalties'),
        Icons.gavel_rounded,
        isArabic ? 'المخالفات' : 'Penalties',
        isArabic ? 'تسجيل ومتابعة' : 'Record & follow up',
        openPenalties,
      ),
      (
        const Key('marketing_quick_search'),
        Icons.person_search_rounded,
        isArabic ? 'البحث' : 'Search',
        isArabic ? 'مناديب وشركات' : 'Delegates & companies',
        openSearch,
      ),
      (
        const Key('marketing_quick_private_label'),
        Icons.sell_rounded,
        'Private Label',
        isArabic ? 'توثيق وتدقيق وتقارير' : 'Capture, audit, reports',
        () => widget.onNavigateTab(3),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 3 : 2;
        final width =
            (constraints.maxWidth - TashilSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: TashilSpacing.sm,
          runSpacing: TashilSpacing.sm,
          children: [
            for (final (i, (key, icon, title, subtitle, onTap))
                in items.indexed)
              SizedBox(
                // An odd last card takes the whole row on phones.
                width: columns == 2 &&
                        items.length.isOdd &&
                        i == items.length - 1
                    ? constraints.maxWidth
                    : width,
                child: _buildActionCard(
                  context: context,
                  key: key,
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
                  onTap: onTap,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card.filled(
      key: key,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.md),
          child: Row(
            children: [
              _primaryIcon(context, icon),
              const SizedBox(width: TashilSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Today's floor check: progress of the walk over today's checked-in
  /// delegates in the favourite branches.
  Widget _buildDailyFloorInspectionOverview(
    BuildContext context,
    bool isArabic,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = TashilSemanticColors.of(context);
    final totalCount = _todayRecords.length;
    final verifiedCount = _todayRecords
        .where((r) => _floorVerifications[r['delegateId']]?.isVerified == true)
        .length;
    final missingCount = _todayRecords
        .where((r) => _floorVerifications[r['delegateId']]?.isMissing == true)
        .length;
    final remainingCount = (totalCount - verifiedCount - missingCount).clamp(
      0,
      totalCount,
    );
    final percent = totalCount > 0 ? (verifiedCount / totalCount) : 0.0;
    final percentInt = (percent * 100).toInt();
    final isComplete = totalCount > 0 && verifiedCount == totalCount;

    final scope = _favoriteBranches.isNotEmpty
        ? (_favoriteBranches.length == 1
              ? _favoriteBranches.first
              : (isArabic
                    ? '${_favoriteBranches.length} فروع مفضلة'
                    : '${_favoriteBranches.length} favourite branches'))
        : (isArabic ? 'لسه ماختارتش فروع' : 'No branches picked yet');

    Widget fact(String label, String value, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color ?? colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Card.filled(
      key: const Key('marketing_home_floor_card'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onNavigateTab(1),
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _primaryIcon(
                    context,
                    isComplete
                        ? Icons.verified_rounded
                        : Icons.fact_check_rounded,
                  ),
                  const SizedBox(width: TashilSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isArabic
                              ? 'المرور اليومي على المناديب'
                              : 'Daily floor check',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          scope,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Bidi.ltr('$percentInt%'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isComplete
                          ? semantic.success
                          : (percentInt == 0
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TashilSpacing.md),
              LinearProgressIndicator(
                value: percent,
                color: isComplete ? semantic.success : null,
              ),
              const SizedBox(height: TashilSpacing.md),
              SkeletonSwitcher(
                loading: _isLoadingAttendance && totalCount == 0,
                skeleton: const Row(
                  children: [
                    Expanded(child: Skeleton(height: 36)),
                    SizedBox(width: TashilSpacing.md),
                    Expanded(child: Skeleton(height: 36)),
                    SizedBox(width: TashilSpacing.md),
                    Expanded(child: Skeleton(height: 36)),
                  ],
                ),
                child: totalCount == 0
                    ? Text(
                        isArabic
                            ? 'مفيش حضور متسجل النهارده في فروعك'
                            : 'No attendance recorded today',
                        key: const Key('marketing_home_floor_empty'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Row(
                        children: [
                          fact(
                            isArabic ? 'حاضر' : 'Present',
                            Bidi.ltr('$totalCount'),
                          ),
                          fact(
                            isArabic ? 'اتراجع' : 'Checked',
                            Bidi.ltr('$verifiedCount'),
                            color: verifiedCount > 0
                                ? semantic.success
                                : colorScheme.onSurfaceVariant,
                          ),
                          fact(
                            isArabic ? 'متبقي' : 'Remaining',
                            Bidi.ltr('$remainingCount'),
                            color: remainingCount > 0
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: TashilSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: const Key('marketing_home_floor_cta'),
                  onPressed: () => widget.onNavigateTab(1),
                  icon: const Icon(Icons.directions_walk_rounded),
                  label: Text(
                    isArabic
                        ? 'ابدأ المرور على المناديب'
                        : 'Start the floor check',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Field reminder: a plain outlined note, no tinted card.
  Widget _buildFieldGuidanceCard(BuildContext context, bool isArabic) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: colorScheme.primary),
            const SizedBox(width: TashilSpacing.md),
            Expanded(
              child: Text(
                isArabic
                    ? 'قبل أي تصوير ترويجي في الفرع، راجع كارنيه المندوب وتاريخ سريان إذن التصوير.'
                    : 'Before any promotional capture, check the delegate ID and the permission expiry date.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
