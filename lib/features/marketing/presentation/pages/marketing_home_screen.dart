import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';

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
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. الكارت الترحيبي والتعريفي الرئيسي مع دليل المهام
            _buildWelcomeDutiesBanner(context, colorScheme, isArabic),

            const SizedBox(height: 20),

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

            // 4. ملخص العمل الميداني والنبض اللحظي
            _buildLiveOperationalOverview(context, colorScheme, isArabic),

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
    final delegate = widget.delegate;
    final displayName = delegate.firstName.isNotEmpty
        ? delegate.firstName
        : delegate.fullName;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.85),
            colorScheme.secondary.withValues(alpha: 0.9),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
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
                      isArabic ? 'أهلاً بك، $displayName 👋' : 'Welcome, $displayName 👋',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              delegate.organizationName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.95),
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
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.storefront_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isArabic ? 'مسؤول تسويق الفروع' : 'Branch Marketing',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // أيقونة بروفايل دائرية
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 14),

          // عنوان دليل المهام والمسؤوليات
          Text(
            isArabic
                ? '📋 دليل المهام والمسؤوليات اليومية لفرعك:'
                : '📋 Your Daily Branch Responsibilities:',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
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
          ),
        ],
      ),
    );
  }

  Widget _buildDutyBullet({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
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
          onTap: () => widget.onNavigateTab(3),
        ),

        // كارت 4: البحث والاستعلام السريع
        _buildActionCard(
          context: context,
          icon: Icons.person_search_rounded,
          iconColor: Colors.teal.shade700,
          cardColor: Colors.teal.withValues(alpha: 0.12),
          borderColor: Colors.teal.withValues(alpha: 0.3),
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

  /// 3. ملخص العمل الميداني والنبض اللحظي
  Widget _buildLiveOperationalOverview(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    final orgId = widget.delegate.organizationUID;

    return StreamBuilder<QuerySnapshot>(
      stream: orgId.isNotEmpty
          ? FirebaseFirestore.instance
              .collectionGroup('photo_permissions')
              .where('status', isEqualTo: 'pending')
              .limit(10)
              .snapshots()
          : const Stream.empty(),
      builder: (context, snapshot) {
        final pendingCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.insights_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isArabic ? 'ملخص النبض الميداني اليومي' : 'Live Field Overview',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // عداد أذونات التصوير المعلقة
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: pendingCount > 0
                            ? Colors.orange.withValues(alpha: 0.12)
                            : colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: pendingCount > 0
                              ? Colors.orange.withValues(alpha: 0.35)
                              : colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.pending_actions_rounded,
                            color: pendingCount > 0
                                ? Colors.orange.shade800
                                : colorScheme.onSurfaceVariant,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$pendingCount',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: pendingCount > 0
                                        ? Colors.orange.shade900
                                        : colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  isArabic
                                      ? 'أذونات بانتظار الاعتماد'
                                      : 'Pending Permissions',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
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
                ],
              ),
            ],
          ),
        );
      },
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
