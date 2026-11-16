import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';

/// عنصر في القائمة الجانبية المكتبية
class HRSidebarItemData {
  final int index;
  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final String? badgeCollection; // اسم المجموعة في فايرستور لعد الطلبات المعلقة
  final Color? badgeColor;
  final bool destructive;

  const HRSidebarItemData({
    required this.index,
    required this.title,
    required this.icon,
    required this.selectedIcon,
    this.badgeCollection,
    this.badgeColor,
    this.destructive = false,
  });
}

/// مجموعة عناصر مبوبة
class HRSidebarSectionData {
  final String sectionTitle;
  final List<HRSidebarItemData> items;

  const HRSidebarSectionData({required this.sectionTitle, required this.items});
}

/// الشريط الجانبي المكتبي المتطور لمنظومة الموارد البشرية (M3 Desktop Sidebar)
class HRDesktopSidebar extends StatelessWidget {
  final Delegate delegate;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onOpenSettings;
  final VoidCallback? onLogout;
  final VoidCallback onOpenProfile;

  const HRDesktopSidebar({
    super.key,
    required this.delegate,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onOpenSettings,
    this.onLogout,
    required this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isArabic = localeProvider.isArabic;

    final sections = WebRuntimePolicy.isWeb
        ? _webSections()
        : _mobileSections();

    final sidebarWidth = isExpanded ? 260.0 : 76.0;

    return AnimatedContainer(
      duration: AppMotionDurations.medium2,
      curve: AppMotionCurves.emphasizedDecelerate,
      width: sidebarWidth,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          // في الـ RTL الخط الفاصل يكون على اليسار
          left: isArabic
              ? BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1.0,
                )
              : BorderSide.none,
          right: !isArabic
              ? BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1.0,
                )
              : BorderSide.none,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header: Logo, Company & Collapse Button ──
          _buildSidebarHeader(context, colorScheme, isArabic),

          // ── Navigation Menu Items ──
          Expanded(
            child: WebRuntimePolicy.isWeb
                ? HrSidebarScrollArea(
                    selectedIndex: selectedIndex,
                    entries: _menuEntries(context, sections, colorScheme),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      for (final entry in _menuEntries(
                        context,
                        sections,
                        colorScheme,
                      ))
                        entry.child,
                    ],
                  ),
          ),

          const Divider(height: 1, thickness: 0.8),

          // ── Footer: Profile, Quick Actions & Settings ──
          _buildSidebarFooter(context, colorScheme, l10n, isArabic),
        ],
      ),
    );
  }

  List<HrSidebarEntry> _menuEntries(
    BuildContext context,
    List<HRSidebarSectionData> sections,
    ColorScheme colorScheme,
  ) => [
    for (final section in sections) ...[
      HrSidebarEntry(
        child: isExpanded
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Text(
                  section.sectionTitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    letterSpacing: 0.4,
                  ),
                ),
              )
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1, indent: 8, endIndent: 8),
              ),
      ),
      for (final item in section.items)
        HrSidebarEntry(
          index: item.index,
          child: _buildMenuItem(
            context: context,
            item: item,
            isSelected: selectedIndex == item.index,
            colorScheme: colorScheme,
          ),
        ),
    ],
  ];

  /// Mobile HR sidebar. Titles and order are the ones the phone already ships.
  List<HRSidebarSectionData> _mobileSections() => const [
    HRSidebarSectionData(
      sectionTitle: 'العمليات والميدان',
      items: [
        HRSidebarItemData(
          index: 0,
          title: 'الحضور والانصراف',
          icon: Icons.how_to_reg_outlined,
          selectedIcon: Icons.how_to_reg_rounded,
        ),
        HRSidebarItemData(
          index: 1,
          title: 'الخريطة الحية',
          icon: Icons.radar_outlined,
          selectedIcon: Icons.radar_rounded,
        ),
        HRSidebarItemData(
          index: 6,
          title: 'الصور والميداني',
          icon: Icons.photo_library_outlined,
          selectedIcon: Icons.photo_library_rounded,
        ),
      ],
    ),
    HRSidebarSectionData(
      sectionTitle: 'إدارة الكوادر',
      items: [
        HRSidebarItemData(
          index: 7,
          title: 'مناديب الشركة',
          icon: Icons.badge_outlined,
          selectedIcon: Icons.badge_rounded,
        ),
        HRSidebarItemData(
          index: 2,
          title: 'طلبات فك الأجهزة',
          icon: Icons.phonelink_lock_outlined,
          selectedIcon: Icons.phonelink_lock_rounded,
          badgeCollection: 'device_unbind_requests',
          badgeColor: Color(0xFFDC2626),
        ),
      ],
    ),
    HRSidebarSectionData(
      sectionTitle: 'الماليات والطلبات',
      items: [
        HRSidebarItemData(
          index: 3,
          title: 'الإجازات والأعذار',
          icon: Icons.event_note_outlined,
          selectedIcon: Icons.event_note_rounded,
          badgeCollection: 'leave_requests',
          badgeColor: Color(0xFFD97706),
        ),
        HRSidebarItemData(
          index: 4,
          title: 'مسيرات الرواتب',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
        ),
      ],
    ),
    HRSidebarSectionData(
      sectionTitle: 'الرقابة والامتثال',
      items: [
        HRSidebarItemData(
          index: 5,
          title: 'سجل الاحتيال',
          icon: Icons.security_outlined,
          selectedIcon: Icons.security_rounded,
        ),
        HRSidebarItemData(
          index: 8,
          title: 'تعديلات الحضور',
          icon: Icons.history_edu_outlined,
          selectedIcon: Icons.history_edu_rounded,
        ),
      ],
    ),
  ];

  /// Web sidebar: every supervisor-menu tool, grouped, without profile (the
  /// header account button opens it) or a second copy of الإعدادات (footer).
  List<HRSidebarSectionData> _webSections() {
    final items = hrShellItems(
      delegate: delegate,
      isWeb: true,
      placement: HrShellPlacement.sidebar,
    );
    final order = <String>[];
    final grouped = <String, List<HRSidebarItemData>>{};
    for (final item in items) {
      final row = HRSidebarItemData(
        index: item.tabIndex ?? -1,
        title: item.title,
        icon: item.icon,
        selectedIcon: item.selectedIcon,
        badgeCollection: item.badgeCollection,
        destructive: item.destructive,
      );
      final bucket = grouped.putIfAbsent(item.section, () {
        order.add(item.section);
        return [];
      });
      bucket.add(row);
    }
    return [
      for (final name in order)
        HRSidebarSectionData(sectionTitle: name, items: grouped[name]!),
    ];
  }

  /// هيدر القائمة الجانبية
  Widget _buildSidebarHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isExpanded ? 14 : 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: isExpanded
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: [
          if (isExpanded) ...[
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.business_center_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'تسهيل',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          delegate.companyName.isNotEmpty
                              ? delegate.companyName
                              : 'بوابة الموارد البشرية',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
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
            IconButton(
              tooltip: isArabic ? 'طي القائمة' : 'Collapse Sidebar',
              icon: Icon(
                Icons.menu_open_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
              onPressed: onToggleExpanded,
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ] else ...[
            IconButton(
              tooltip: isArabic ? 'توسيع القائمة' : 'Expand Sidebar',
              icon: Icon(
                Icons.menu_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 22,
              ),
              onPressed: onToggleExpanded,
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// عنصر القائمة الفردي بتصميم M3 الكبسولي
  Widget _buildMenuItem({
    required BuildContext context,
    required HRSidebarItemData item,
    required bool isSelected,
    required ColorScheme colorScheme,
  }) {
    final itemColor = item.destructive
        ? colorScheme.error
        : isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    Widget iconWidget = Icon(
      isSelected ? item.selectedIcon : item.icon,
      size: 20,
      color: itemColor,
    );

    // إضافة شارة العداد الحي إذا كان العنصر مرتبطاً بطلبات معلقة
    if (item.badgeCollection != null) {
      Stream<QuerySnapshot>? pending;
      try {
        pending = FirebaseFirestore.instance
            .collection(item.badgeCollection!)
            .where('companyUID', isEqualTo: delegate.companyUID)
            .where('status', isEqualTo: 'pending')
            .snapshots();
      } catch (_) {
        pending = null;
      }
      if (pending == null) {
        // Firebase isn't ready (tests, or a build without a default app).
      } else {
        iconWidget = StreamBuilder<QuerySnapshot>(
          stream: pending,
          builder: (context, snapshot) {
            final count = snapshot.data?.docs.length ?? 0;
            return Badge(
              isLabelVisible: count > 0,
              label: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: item.badgeColor ?? colorScheme.error,
              textColor: Colors.white,
              child: Icon(
                isSelected ? item.selectedIcon : item.icon,
                size: 20,
                color: itemColor,
              ),
            );
          },
        );
      }
    }

    final content = AnimatedContainer(
      duration: AppMotionDurations.short3,
      curve: AppMotionCurves.standardDecelerate,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.symmetric(
        horizontal: isExpanded ? 12 : 8,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: isExpanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          iconWidget,
          if (isExpanded) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: item.destructive
                      ? colorScheme.error
                      : isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (item.index < 0) {
            onOpenProfile();
          } else {
            onItemSelected(item.index);
          }
        },
        borderRadius: BorderRadius.circular(14),
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: isExpanded
            ? content
            : Tooltip(
                message: item.title,
                waitDuration: const Duration(milliseconds: 300),
                child: content,
              ),
      ),
    );
  }

  /// Footer. Web keeps only الإعدادات; the profile block lives in the header.
  /// Mobile still shows the profile block above settings.
  Widget _buildSidebarFooter(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
    bool isArabic,
  ) {
    final showProfile = !WebRuntimePolicy.isWeb;
    return Container(
      padding: EdgeInsets.all(isExpanded ? 12 : 8),
      child: Column(
        children: [
          if (showProfile) ...[
            if (isExpanded)
              InkWell(
                onTap: onOpenProfile,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      AppAvatar(
                        imageUrl: delegate.personalPhotoUrl,
                        fallbackText: delegate.fullName.isNotEmpty
                            ? delegate.fullName[0]
                            : 'H',
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              delegate.fullName.isNotEmpty
                                  ? delegate.fullName
                                  : 'مسؤول الموارد البشرية',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                delegate.role == UserRole.admin
                                    ? 'مشرف الشركة'
                                    : 'موارد بشرية (HR)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              IconButton(
                tooltip: l10n.profile,
                icon: AppAvatar(
                  imageUrl: delegate.personalPhotoUrl,
                  fallbackText: delegate.fullName.isNotEmpty
                      ? delegate.fullName[0]
                      : 'H',
                  radius: 16,
                ),
                onPressed: onOpenProfile,
              ),
            const SizedBox(height: 6),
          ],

          // زر الإعدادات فقط في الأسفل (تم نقل الثيم للهيدر واللغة والخروج داخل الإعدادات لتجنب الـ Overflow)
          if (isExpanded)
            InkWell(
              onTap: onOpenSettings,
              borderRadius: BorderRadius.circular(12),
              hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.settings,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
              tooltip: l10n.settings,
              icon: Icon(
                Icons.settings_outlined,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: onOpenSettings,
            ),
        ],
      ),
    );
  }
}

/// One row of the sidebar list. [index] is the tab the row opens (or -1 for
/// the profile row); section headers have none.
class HrSidebarEntry {
  final int? index;
  final Widget child;

  const HrSidebarEntry({this.index, required this.child});
}

/// Web: the menu scrolls on its own between the header and the pinned footer,
/// with a visible scrollbar, so the last tools are never hidden behind
/// الإعدادات. The selected row is scrolled into view.
class HrSidebarScrollArea extends StatefulWidget {
  final int selectedIndex;
  final List<HrSidebarEntry> entries;

  const HrSidebarScrollArea({
    super.key,
    required this.selectedIndex,
    required this.entries,
  });

  @override
  State<HrSidebarScrollArea> createState() => _HrSidebarScrollAreaState();
}

class _HrSidebarScrollAreaState extends State<HrSidebarScrollArea> {
  final ScrollController _controller = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    _revealSelected(animate: false);
  }

  @override
  void didUpdateWidget(HrSidebarScrollArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _revealSelected(animate: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _revealSelected({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final row = _rowKeys[widget.selectedIndex]?.currentContext
          ?.findRenderObject();
      if (row == null || !row.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(row);
      if (viewport == null) return;
      final position = _controller.position;
      final atTop = viewport.getOffsetToReveal(row, 0).offset;
      final atBottom = viewport.getOffsetToReveal(row, 1).offset;
      final double target;
      if (position.pixels > atTop) {
        target = atTop;
      } else if (position.pixels < atBottom) {
        target = atBottom;
      } else {
        return;
      }
      final clamped = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (animate) {
        _controller.animateTo(
          clamped,
          duration: AppMotionDurations.medium2,
          curve: AppMotionCurves.emphasizedDecelerate,
        );
      } else {
        _controller.jumpTo(clamped);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          key: const ValueKey('hr_sidebar_scroll'),
          controller: _controller,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in widget.entries)
                entry.index == null
                    ? entry.child
                    : KeyedSubtree(
                        key: _rowKeys.putIfAbsent(entry.index!, GlobalKey.new),
                        child: entry.child,
                      ),
            ],
          ),
        ),
      ),
    );
  }
}
