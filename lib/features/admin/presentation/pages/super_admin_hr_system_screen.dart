import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_monthly_payroll_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tracking/presentation/pages/delegate_tracking_screen.dart';
import 'package:flutter/material.dart';

/// شاشة نظام الموارد البشرية (HR System) المخصصة للسوبر أدمن.
/// تجمع كافة أدوات الموارد البشرية الخمسة في واجهة مركزية موحدة:
/// 1. سجل الحضور والانصراف
/// 2. التتبع المباشر (Live Tracking)
/// 3. طلبات الإجازات والأعذار
/// 4. مسير الرواتب والعمولات
/// 5. سجل تعديلات الحضور والانصراف
class SuperAdminHRSystemScreen extends StatelessWidget {
  final Delegate delegate;

  const SuperAdminHRSystemScreen({
    super.key,
    required this.delegate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'HR System',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'نظام الموارد البشرية وإدارة شؤون الموظفين',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 768;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 24 : 16,
                  vertical: 16,
                ),
                children: [
                  _HRHeaderBanner(delegate: delegate),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.dashboard_customize_rounded, size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'أقسام ووحدات الموارد البشرية',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isDesktop)
                    _buildDesktopGrid(context)
                  else
                    _buildMobileList(context),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<_HRModuleItem> _getModules(BuildContext context) {
    return [
      _HRModuleItem(
        title: 'سجل الحضور والانصراف',
        subtitle: 'متابعة سجلات الحضور والانصراف اليومية للمناديب والموظفين، ساعات العمل، ومطابقة النطاق الجغرافي.',
        icon: Icons.co_present_rounded,
        accentColor: Theme.of(context).colorScheme.primary,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HRAttendanceScreen(
                hrDelegate: delegate,
                showAppBar: true,
              ),
            ),
          );
        },
      ),
      _HRModuleItem(
        title: 'Live Tracking',
        badgeLabel: 'مباشر',
        subtitle: 'المراقبة الحية لمواقع المناديب والمروجين على الخريطة، متابعة خطوط السير والتواجد في الفروع لحظياً.',
        icon: Icons.radar_rounded,
        accentColor: Colors.teal,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DelegateTrackingScreen(
                adminDelegate: delegate,
              ),
            ),
          );
        },
      ),
      _HRModuleItem(
        title: 'طلبات الإجازات والأعذار',
        subtitle: 'مراجعة واعتماد طلبات الإجازات السنوية والمرضية وأعذار الغياب، ومتابعة أرصدة الإجازات المتاحة.',
        icon: Icons.event_note_rounded,
        accentColor: Theme.of(context).colorScheme.tertiary,
        badgeStream: _pendingLeavesStream(),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HRLeavesAndExcusesScreen(
                hrDelegate: delegate,
                showAppBar: true,
              ),
            ),
          );
        },
      ),
      _HRModuleItem(
        title: 'مسير الرواتب والعمولات',
        subtitle: 'احتساب أيام وساعات العمل الفعلية، مسيرات الرواتب الشهرية، الحوافز، والخصومات المعتمدة.',
        icon: Icons.account_balance_wallet_rounded,
        accentColor: const Color(0xFF2E7D32), // Elegant green
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HRMonthlyPayrollScreen(
                hrDelegate: delegate,
                showAppBar: true,
              ),
            ),
          );
        },
      ),
      _HRModuleItem(
        title: 'سجل تعديلات الحضور والانصراف',
        subtitle: 'سجل تدقيق شامل ومؤرشف لكافة التعديلات الإدارية والاستثنائية التي تمت على أوقات الحضور والانصراف.',
        icon: Icons.history_edu_rounded,
        accentColor: Theme.of(context).colorScheme.secondary,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HRAttendanceAdjustmentsScreen(
                hrDelegate: delegate,
                showAppBar: true,
              ),
            ),
          );
        },
      ),
    ];
  }

  Stream<int> _pendingLeavesStream() {
    try {
      var query = FirebaseFirestore.instance.collection('leave_requests');
      if (delegate.companyUID.isNotEmpty) {
        return query
            .where('companyUID', isEqualTo: delegate.companyUID)
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((snap) => snap.docs.length);
      }
      return query
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snap) => snap.docs.length);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Widget _buildDesktopGrid(BuildContext context) {
    final modules = _getModules(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 2.3,
      ),
      itemCount: modules.length,
      itemBuilder: (context, index) {
        return _HRModuleCard(module: modules[index]);
      },
    );
  }

  Widget _buildMobileList(BuildContext context) {
    final modules = _getModules(context);
    return Column(
      children: [
        for (final module in modules) ...[
          _HRModuleCard(module: module),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _HRModuleItem {
  final String title;
  final String? badgeLabel;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final Stream<int>? badgeStream;

  const _HRModuleItem({
    required this.title,
    this.badgeLabel,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.badgeStream,
  });
}

class _HRModuleCard extends StatefulWidget {
  final _HRModuleItem module;

  const _HRModuleCard({required this.module});

  @override
  State<_HRModuleCard> createState() => _HRModuleCardState();
}

class _HRModuleCardState extends State<_HRModuleCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final item = widget.module;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: AppMotionDurations.short3,
        curve: AppMotionCurves.standard,
        decoration: BoxDecoration(
          color: _isHovered
              ? cs.surfaceContainerHigh
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? item.accentColor.withValues(alpha: 0.5)
                : cs.outlineVariant.withValues(alpha: 0.6),
            width: _isHovered ? 1.4 : 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: item.accentColor.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Subtle colored start border line conforming to border radius (anti-aliased)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: isArabic ? 0 : null,
                  left: isArabic ? null : 0,
                  width: 4,
                  child: Container(
                    color: item.accentColor,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Module Icon Container
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: item.accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: item.accentColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(
                          item.icon,
                          size: 24,
                          color: item.accentColor,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Text Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    item.title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.badgeLabel != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: item.accentColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.badgeLabel!,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: item.accentColor,
                                      ),
                                    ),
                                  ),
                                ],
                                if (item.badgeStream != null) ...[
                                  const SizedBox(width: 8),
                                  StreamBuilder<int>(
                                    stream: item.badgeStream,
                                    builder: (context, snapshot) {
                                      final count = snapshot.data ?? 0;
                                      if (count <= 0) return const SizedBox.shrink();
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.error,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '$count جديد',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: cs.onError,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Navigation Arrow
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isArabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HRHeaderBanner extends StatelessWidget {
  final Delegate delegate;

  const _HRHeaderBanner({required this.delegate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary,
                  cs.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.badge_rounded,
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
                    Text(
                      'نظام الموارد البشرية',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'HR System',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'مركز إدارة الحضور والانصراف، التتبع الميداني، طلبات الإجازات والأعذار، ومسيرات الرواتب للمؤسسة.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
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
}
