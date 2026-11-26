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
  bool get _canViewReports => _isSuperAdmin || (_permissions?.canViewReports ?? false);
  bool get _canReviewAudit => _isSuperAdmin || (_permissions?.canReviewAudit ?? false);

  @override
  void initState() {
    super.initState();
    _listenToPermissions();
  }

  void _listenToPermissions() {
    _permissionsSubscription = di.sl<PrivateLabelPermissionsRemoteDataSource>()
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

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(
                isArabic ? 'مركز العلامة الخاصة (Private Label)' : 'Private Label Hub',
              ),
              centerTitle: false,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
          await Future.delayed(const Duration(milliseconds: 400));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. الكارت التعريفي الرئيسي لمركز عمليات Private Label
                  _buildHubBanner(context, colorScheme, isArabic),

                  const SizedBox(height: 16),

                  // 2. كارت الـ KPI ومتابعة التوثيق اليومي للمسوق (إذا كانت لديه صلاحية التوثيق)
                  if (_canCapture) ...[
                    _buildKpiSection(context, colorScheme, isArabic),
                    const SizedBox(height: 20),
                  ],

                  // 3. عنوان أدوات وميزات العلامة الخاصة
                  Row(
                    children: [
                      Icon(
                        Icons.dashboard_customize_rounded,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isArabic ? 'أدوات وعمليات العلامة الخاصة' : 'Private Label Tools & Modules',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sell_rounded, size: 13, color: colorScheme.primary),
                            const SizedBox(width: 5),
                            Text(
                              isArabic ? 'مساحة العمل' : 'Workspace',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 4. شبكة / قائمة الأدوات والميزات الأساسية
                  _buildToolsList(context, colorScheme, isArabic),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 1. الكارت التعريفي الرئيسي لـ Private Label Hub
  Widget _buildHubBanner(BuildContext context, ColorScheme colorScheme, bool isArabic) {
    final theme = Theme.of(context);
    final delegate = widget.delegate;
    final displayName = delegate.firstName.isNotEmpty ? delegate.firstName : delegate.fullName;

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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.sell_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isArabic ? 'مركز العلامة الخاصة' : 'Private Label Hub',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
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
                    const SizedBox(height: 4),
                    Text(
                      isArabic
                          ? 'مرحباً $displayName، هذا هو المركز الموحد لإدارة وتطوير كافة عمليات التوثيق الميداني، مراجعة وتدقيق الأسعار، وتقارير أداء الفروع والمسوقين.'
                          : 'Welcome $displayName, this is your unified hub for field documentation, price audits, and performance reports.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // مؤشرات الصلاحيات الحالية
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPermissionPill(
                icon: Icons.camera_alt_rounded,
                label: 'التوثيق الميداني',
                isActive: _canCapture,
                colorScheme: colorScheme,
              ),
              _buildPermissionPill(
                icon: Icons.fact_check_rounded,
                label: 'التدقيق والاعتماد',
                isActive: _canReviewAudit,
                colorScheme: colorScheme,
              ),
              _buildPermissionPill(
                icon: Icons.analytics_rounded,
                label: 'التقارير والإحصائيات',
                isActive: _canViewReports,
                colorScheme: colorScheme,
              ),
              if (_isSuperAdmin)
                _buildPermissionPill(
                  icon: Icons.admin_panel_settings_rounded,
                  label: 'مدير النظام (كامل الصلاحيات)',
                  isActive: true,
                  colorScheme: colorScheme,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionPill({
    required IconData icon,
    required String label,
    required bool isActive,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            isActive ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            size: 12,
            color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  /// 2. كارت الـ KPI الشهري وحالة اليوم
  Widget _buildKpiSection(BuildContext context, ColorScheme colorScheme, bool isArabic) {
    if (!di.sl.isRegistered<PrivateLabelBloc>()) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              isArabic ? 'إنجاز التوثيق والـ KPI الشهري' : 'Monthly KPI & Documentation',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PrivateLabelHomeCard(delegate: widget.delegate),
      ],
    );
  }

  /// 4. شبكة وقائمة الأدوات والميزات
  Widget _buildToolsList(BuildContext context, ColorScheme colorScheme, bool isArabic) {
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
          statusPillText: _canReviewAudit ? (isArabic ? 'متاح للاعتماد' : 'Active') : (isArabic ? 'يتطلب صلاحية' : 'Restricted'),
          isPermitted: _canReviewAudit,
          onTap: () {
            if (_canReviewAudit) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PrivateLabelReviewScreen(delegate: widget.delegate),
                ),
              );
            } else {
              _handleLockedFeature(context, 'Private Label Audit');
            }
          },
        ),

        const SizedBox(height: 12),

        // أداة 2: Private Label Report
        _buildToolCard(
          context: context,
          icon: Icons.analytics_rounded,
          iconBgColor: colorScheme.secondaryContainer,
          iconColor: colorScheme.onSecondaryContainer,
          title: 'Private Label Report',
          arabicSubtitle: 'مؤشر ونسب إنجاز الفروع',
          statusPillText: _canViewReports ? (isArabic ? 'تقارير شهرية' : 'Reports') : (isArabic ? 'يتطلب صلاحية' : 'Restricted'),
          isPermitted: _canViewReports,
          onTap: () {
            if (_canViewReports) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PrivateLabelReportScreen(delegate: widget.delegate),
                ),
              );
            } else {
              _handleLockedFeature(context, 'Private Label Report');
            }
          },
        ),

        const SizedBox(height: 12),

        // أداة 3: Private Label Capture
        _buildToolCard(
          context: context,
          icon: Icons.camera_alt_rounded,
          iconBgColor: colorScheme.tertiaryContainer,
          iconColor: colorScheme.onTertiaryContainer,
          title: 'Private Label Capture',
          arabicSubtitle: 'التوثيق الميداني اليومي للمنتجات',
          statusPillText: _canCapture ? (isArabic ? 'توثيق يومي' : 'Capture') : (isArabic ? 'يتطلب صلاحية' : 'Restricted'),
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

        const SizedBox(height: 12),

        // أداة 4: Private Label Catalog
        Builder(
          builder: (context) {
            final canEdit = PrivateLabelCatalogScreen.canEditCatalog(widget.delegate);
            final canOpenCatalog = _canReviewAudit ||
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
          const SizedBox(height: 12),
          _buildToolCard(
            context: context,
            icon: Icons.admin_panel_settings_rounded,
            iconBgColor: colorScheme.errorContainer.withValues(alpha: 0.6),
            iconColor: colorScheme.onErrorContainer,
            title: 'إدارة صلاحيات Private Label',
            arabicSubtitle: 'توزيع وتعديل صلاحيات التوثيق والتدقيق والتقارير لمسؤولي التسويق في النظام',
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

  /// ويدجت الكارت الفردي لأي أداة من أدوات Private Label
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isPermitted
              ? colorScheme.outlineVariant
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: colorScheme.primary.withValues(alpha: 0.05),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPermitted ? iconBgColor : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: isPermitted ? iconColor : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isPermitted ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPermitted
                                ? colorScheme.primary.withValues(alpha: 0.08)
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isPermitted
                                  ? colorScheme.primary.withValues(alpha: 0.2)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            statusPillText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isPermitted
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      arabicSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isPermitted ? Icons.arrow_forward_ios_rounded : Icons.lock_outline_rounded,
                size: 15,
                color: isPermitted ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
