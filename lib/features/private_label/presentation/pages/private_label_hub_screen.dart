import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/pull_to_refresh.dart';
import 'package:delegate_app/core/design/widgets/summary_card.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_screen.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_review_screen.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_report_screen.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_catalog_screen.dart';
import 'package:delegate_app/features/private_label/presentation/pages/super_admin_private_label_permissions_screen.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_home_card.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// شاشة مركز عمليات العلامة الخاصة (Private Label Hub)
/// تجمع وتوحد كافة أدوات وعمليات Private Label في مكان واحد:
/// 1. التدقيق والاعتماد (Private Label Audit)
/// 2. التقارير وإحصائيات الأداء (Private Label Report)
/// 3. التوثيق الميداني اليومي والتقويم (Private Label Capture)
/// 4. كتالوج منتجات العلامة الخاصة (Private Label Catalog)
/// 5. إدارة الصلاحيات (Super Admin Permissions)
class PrivateLabelHubScreen extends StatefulWidget {
  final Delegate delegate;
  final Function(int tabIndex)? onNavigateTab;
  final bool showAppBar;

  const PrivateLabelHubScreen({
    super.key,
    required this.delegate,
    this.onNavigateTab,
    this.showAppBar = false,
  });

  @override
  State<PrivateLabelHubScreen> createState() => _PrivateLabelHubScreenState();
}

class _PrivateLabelHubScreenState extends State<PrivateLabelHubScreen> {
  StreamSubscription<PrivateLabelPermissions?>? _permissionsSubscription;
  PrivateLabelPermissions? _permissions;

  bool get _isSuperAdmin => widget.delegate.role == UserRole.superAdmin;
  bool get _canCapture => _isSuperAdmin || (_permissions?.canCapture ?? false);
  bool get _canViewReports =>
      _isSuperAdmin || (_permissions?.canViewReports ?? false);
  bool get _canReviewAudit =>
      _isSuperAdmin || (_permissions?.canReviewAudit ?? false);

  @override
  void initState() {
    super.initState();
    _listenToPermissions();
  }

  void _listenToPermissions() {
    _permissionsSubscription = di
        .sl<PrivateLabelPermissionsRemoteDataSource>()
        .streamUserPermissions(widget.delegate.uid)
        .listen((perms) {
          if (mounted) {
            setState(() {
              _permissions = perms;
            });
          }
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _permissionsSubscription?.cancel();
    super.dispose();
  }

  void _handleLockedFeature(BuildContext context, String featureName) {
    AppSnackBar.showInfo(
      context,
      'ميزة "$featureName" تتطلب صلاحية خاصة. يمكنك مراجعة مدير النظام لمنح الصلاحية.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsetsDirectional.only(
        start: TashilSpacing.xs,
        bottom: TashilSpacing.sm,
      ),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    // TAS-392: same page skeleton as the delegate pages: kit refresh,
    // section titles, one card style (SummaryCard) per tool.
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(
                isArabic
                    ? 'مركز العلامة الخاصة (Private Label)'
                    : 'Private Label Hub',
              ),
            )
          : null,
      body: PullToRefresh(
        onRefresh: () async => setState(() {}),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.fromSTEB(
            TashilSpacing.lg,
            TashilSpacing.md,
            TashilSpacing.lg,
            TashilSpacing.xxl,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHubBanner(context, colorScheme, isArabic),
                    const SizedBox(height: TashilSpacing.lg),
                    if (_canCapture) ...[
                      _buildKpiSection(context, colorScheme, isArabic),
                      const SizedBox(height: TashilSpacing.lg),
                    ],
                    sectionTitle(isArabic ? 'الأدوات' : 'Tools'),
                    _buildToolsList(context, colorScheme, isArabic),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Your Private Label permissions, as icon + text rows (read-only values,
  /// not chips).
  Widget _buildHubBanner(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    final theme = Theme.of(context);
    final rows = <(IconData, String, bool)>[
      (Icons.camera_alt_rounded, 'التوثيق الميداني', _canCapture),
      (Icons.fact_check_rounded, 'التدقيق والاعتماد', _canReviewAudit),
      (Icons.analytics_rounded, 'التقارير والإحصائيات', _canViewReports),
      if (_isSuperAdmin)
        (Icons.admin_panel_settings_rounded, 'مدير النظام', true),
    ];
    return Card.filled(
      key: const Key('private_label_permissions_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(TashilRadius.medium),
                  ),
                  child: Icon(Icons.sell_rounded, color: colorScheme.onPrimary),
                ),
                const SizedBox(width: TashilSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArabic ? 'مركز العلامة الخاصة' : 'Private Label Hub',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        isArabic
                            ? 'التوثيق والتدقيق والتقارير في مكان واحد'
                            : 'Capture, audit and reports in one place',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: TashilSpacing.md),
            Text(
              isArabic ? 'صلاحياتك' : 'Your access',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            for (final (icon, label, on) in rows)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: TashilSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: TashilSpacing.sm),
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyMedium),
                    ),
                    Icon(
                      on
                          ? Icons.check_circle_rounded
                          : Icons.lock_outline_rounded,
                      size: 18,
                      color: on
                          ? TashilSemanticColors.of(context).success
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: TashilSpacing.xs),
                    Text(
                      on ? 'متاحة' : 'مقفولة',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 2. كارت الـ KPI الشهري وحالة اليوم
  Widget _buildKpiSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    if (!di.sl.isRegistered<PrivateLabelBloc>()) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: TashilSpacing.xs,
            bottom: TashilSpacing.sm,
          ),
          child: Text(
            isArabic ? 'إنجاز الشهر' : 'This month',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        PrivateLabelHomeCard(delegate: widget.delegate),
      ],
    );
  }

  /// 4. شبكة وقائمة الأدوات والميزات
  Widget _buildToolsList(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Column(
      children: [
        // أداة 1: Private Label Audit
        _buildToolCard(
          context: context,
          icon: Icons.fact_check_rounded,
          iconBgColor: colorScheme.primaryContainer,
          iconColor: colorScheme.onPrimaryContainer,
          title: 'Private Label Audit',
          arabicSubtitle: 'مراجعة وتدقيق المنتجات',
          statusPillText: _canReviewAudit
              ? (isArabic ? 'متاح للاعتماد' : 'Active')
              : (isArabic ? 'يتطلب صلاحية' : 'Restricted'),
          isPermitted: _canReviewAudit,
          onTap: () {
            if (_canReviewAudit) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PrivateLabelReviewScreen(delegate: widget.delegate),
                ),
              );
            } else {
              _handleLockedFeature(context, 'Private Label Audit');
            }
          },
        ),

        const SizedBox(height: TashilSpacing.xs),

        // أداة 2: Private Label Report
        _buildToolCard(
          context: context,
          icon: Icons.analytics_rounded,
          iconBgColor: colorScheme.secondaryContainer,
          iconColor: colorScheme.onSecondaryContainer,
          title: 'Private Label Report',
          arabicSubtitle: 'مؤشر ونسب إنجاز الفروع',
          statusPillText: _canViewReports
              ? (isArabic ? 'تقارير شهرية' : 'Reports')
              : (isArabic ? 'يتطلب صلاحية' : 'Restricted'),
          isPermitted: _canViewReports,
          onTap: () {
            if (_canViewReports) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PrivateLabelReportScreen(delegate: widget.delegate),
                ),
              );
            } else {
              _handleLockedFeature(context, 'Private Label Report');
            }
          },
        ),

        const SizedBox(height: TashilSpacing.xs),

        // أداة 3: Private Label Capture
        _buildToolCard(
          context: context,
          icon: Icons.camera_alt_rounded,
          iconBgColor: colorScheme.tertiaryContainer,
          iconColor: colorScheme.onTertiaryContainer,
          title: 'Private Label Capture',
          arabicSubtitle: 'التوثيق الميداني اليومي للمنتجات',
          statusPillText: _canCapture
              ? (isArabic ? 'توثيق يومي' : 'Capture')
              : (isArabic ? 'يتطلب صلاحية' : 'Restricted'),
          isPermitted: _canCapture,
          onTap: () {
            if (_canCapture) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PrivateLabelScreen(delegate: widget.delegate),
                ),
              );
            } else {
              _handleLockedFeature(context, 'Private Label Capture');
            }
          },
        ),

        const SizedBox(height: TashilSpacing.xs),

        // أداة 4: Private Label Catalog
        Builder(
          builder: (context) {
            final canEdit = PrivateLabelCatalogScreen.canEditCatalog(
              widget.delegate,
            );
            final canOpenCatalog =
                _canReviewAudit ||
                _canCapture ||
                widget.delegate.role == UserRole.marketing ||
                widget.delegate.role == UserRole.branchesMarketingManager ||
                widget.delegate.role == UserRole.organizationAdmin;
            return _buildToolCard(
              context: context,
              icon: Icons.inventory_2_rounded,
              iconBgColor: colorScheme.surfaceContainerHighest,
              iconColor: colorScheme.primary,
              title: 'Private Label Catalog',
              arabicSubtitle: canEdit
                  ? 'صفحة الكتالوج وإضافة وتعديل المنتجات'
                  : 'صفحة الكتالوج وعرض المنتجات والأسعار المعتمدة',
              statusPillText: canOpenCatalog
                  ? (isArabic ? 'الكتالوج' : 'Catalog')
                  : (isArabic ? 'يتطلب صلاحية' : 'Restricted'),
              isPermitted: canOpenCatalog,
              onTap: () {
                if (canOpenCatalog) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PrivateLabelCatalogScreen(
                        delegate: widget.delegate,
                        readOnly: !canEdit,
                      ),
                    ),
                  );
                } else {
                  _handleLockedFeature(context, 'Private Label Catalog');
                }
              },
            );
          },
        ),

        // أداة 5: إدارة الصلاحيات (Super Admin فقط)
        if (_isSuperAdmin) ...[
          const SizedBox(height: TashilSpacing.xs),
          _buildToolCard(
            context: context,
            icon: Icons.admin_panel_settings_rounded,
            iconBgColor: colorScheme.errorContainer,
            iconColor: colorScheme.onErrorContainer,
            title: 'إدارة صلاحيات Private Label',
            arabicSubtitle:
                'توزيع وتعديل صلاحيات التوثيق والتدقيق والتقارير لمسؤولي التسويق في النظام',
            statusPillText: 'Super Admin',
            isPermitted: true,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SuperAdminPrivateLabelPermissionsScreen(
                    adminDelegate: widget.delegate,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  /// One tool = one SummaryCard (P-07). A locked tool keeps its card but
  /// shows a lock and "needs access" instead of the arrow.
  Widget _buildToolCard({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String arabicSubtitle,
    required String statusPillText,
    required bool isPermitted,
    required VoidCallback onTap,
  }) {
    return SummaryCard(
      key: ValueKey('private_label_tool_$title'),
      icon: icon,
      title: title,
      subtitle: arabicSubtitle,
      action: isPermitted
          ? null
          : Tooltip(
              message: statusPillText,
              child: Icon(
                Icons.lock_outline_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
      margin: EdgeInsets.zero,
      onTap: onTap,
    );
  }
}
