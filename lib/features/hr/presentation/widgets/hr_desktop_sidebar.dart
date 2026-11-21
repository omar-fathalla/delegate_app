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
import 'package:delegate_app/web/hr_system/hr_overlay_scrollbar.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// عنصر في القائمة الجانبية المكتبية
class HRSidebarItemData {
  final int index;
  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final String? badgeCollection; // اسم المجموعة في فايرستور لعد الطلبات المعلقة
  /// Rail badge tone. `true` = warning (amber), `false` = danger (error).
  final bool badgeWarning;
  final bool destructive;

  const HRSidebarItemData({
    required this.index,
    required this.title,
    required this.icon,
    required this.selectedIcon,
    this.badgeCollection,
    this.badgeWarning = false,
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
      clipBehavior: Clip.hardEdge,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On web, labels follow the animated width so the expand/collapse
          // frames never lay an expanded row out in the rail's narrow slot
          // (that paints the red overflow stripe). Mobile still follows the
          // expanded flag, so its layout is unchanged.
          final showLabels = WebRuntimePolicy.isWeb
              ? constraints.maxWidth >= 180
              : isExpanded;
          return Column(
            children: [
              _buildSidebarHeader(context, colorScheme, isArabic, showLabels),
              Expanded(
                child: WebRuntimePolicy.isWeb
                    ? HrSidebarScrollArea(
                        selectedIndex: selectedIndex,
                        padding: EdgeInsets.fromLTRB(
                          showLabels ? 10 : 0,
                          12,
                          showLabels ? 10 : 0,
                          16,
                        ),
                        entries: _menuEntries(
                          context,
                          sections,
                          colorScheme,
                          showLabels,
                        ),
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
                            showLabels,
                          ))
                            entry.child,
                        ],
                      ),
              ),
              const Divider(height: 1, thickness: 0.8),
              _buildSidebarFooter(
                context,
                colorScheme,
                l10n,
                isArabic,
                showLabels,
              ),
            ],
          );
        },
      ),
    );
  }

  List<HrSidebarEntry> _menuEntries(
    BuildContext context,
    List<HRSidebarSectionData> sections,
    ColorScheme colorScheme,
    bool showLabels,
  ) => [
    for (var i = 0; i < sections.length; i++) ...[
      if (WebRuntimePolicy.isWeb && i > 0)
        HrSidebarEntry(child: _groupDivider(colorScheme)),
      // Mobile keeps a plain section header (a title when expanded, the
      // original rail divider when collapsed). Web adds the divider above
      // and still shows the group title only while the labels fit. The
      // «الرئيسية» header is omitted because it repeats the first item.
      if (!(WebRuntimePolicy.isWeb && sections[i].sectionTitle == 'الرئيسية') &&
          (showLabels || !WebRuntimePolicy.isWeb))
        HrSidebarEntry(
          child: showLabels
              ? Padding(
                  // M3 drawer section headline: titleSmall, onSurfaceVariant.
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    sections[i].sectionTitle,
                    style: TextStyle(
                      fontSize: HrFont.body,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, indent: 8, endIndent: 8),
                ),
        ),
      for (final item in sections[i].items)
        HrSidebarEntry(
          index: item.index,
          child: _buildMenuItem(
            context: context,
            item: item,
            isSelected: selectedIndex == item.index,
            colorScheme: colorScheme,
            showLabels: showLabels,
          ),
        ),
    ],
  ];

  /// Thin group separator for the web sidebar and the collapsed rail.
  Widget _groupDivider(ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        isExpanded ? 8 : 12,
        6,
        isExpanded ? 8 : 12,
        6,
      ),
      child: Divider(
        height: 1,
        thickness: 1,
        color: colorScheme.outlineVariant,
      ),
    );
  }

  /// Mobile HR sidebar. Titles and order are the ones the phone already ships.
  List<HRSidebarSectionData> _mobileSections() => [
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
          badgeWarning: true,
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
      // «نظام الغرامات» keeps the same colors as every other row.
      final row = HRSidebarItemData(
        index: item.tabIndex ?? -1,
        title: item.menuLabel(isWeb: true),
        icon: item.icon,
        selectedIcon: item.selectedIcon,
        badgeCollection: item.badgeCollection,
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
    bool showLabels,
  ) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: showLabels ? 14 : 10),
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
        mainAxisAlignment: showLabels
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: [
          if (showLabels) ...[
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
                      borderRadius: BorderRadius.circular(HrRadius.card),
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
                            fontSize: HrFont.titleMedium,
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
                            fontSize: HrFont.labelSmall,
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
            _railIconButton(
              tooltip: isArabic ? 'طي القائمة' : 'Collapse Sidebar',
              icon: Icon(
                Icons.menu_open_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
              onPressed: onToggleExpanded,
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
              ),
            ),
          ] else ...[
            _railIconButton(
              tooltip: isArabic ? 'توسيع القائمة' : 'Expand Sidebar',
              icon: Icon(
                Icons.menu_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 22,
              ),
              onPressed: onToggleExpanded,
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HrRadius.chip),
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
    required bool showLabels,
  }) {
    final web = WebRuntimePolicy.isWeb;
    // Web selected rows use the drawer indicator. Error red stays available
    // for a destructive mobile row; the web catalog's gavel is not one.
    final selectedColor = web
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimaryContainer;
    final iconColor = !web && item.destructive
        ? colorScheme.error
        : isSelected
        ? selectedColor
        : colorScheme.onSurfaceVariant;
    final labelColor = !web && item.destructive
        ? colorScheme.error
        : isSelected
        ? selectedColor
        : colorScheme.onSurface;

    Widget iconWidget = Icon(
      isSelected ? item.selectedIcon : item.icon,
      size: 20,
      color: iconColor,
    );

    // إضافة شارة العداد الحي إذا كان العنصر مرتبطاً بطلبات معلقة
    Stream<int>? pendingCount;
    if (item.badgeCollection != null) {
      try {
        pendingCount = FirebaseFirestore.instance
            .collection(item.badgeCollection!)
            .where('companyUID', isEqualTo: delegate.companyUID)
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((s) => s.docs.length);
      } catch (_) {
        // Firebase isn't ready (tests, or a build without a default app).
        pendingCount = null;
      }
    }

    // Web drawer rows show the count as trailing text beside the label
    // (M3 navigation drawer badge). The collapsed rail and mobile keep a
    // Badge on the icon, toned danger or warning from the theme.
    final trailingBadge = web && showLabels;
    Widget? trailing;
    if (pendingCount != null && trailingBadge) {
      trailing = StreamBuilder<int>(
        stream: pendingCount,
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          if (count == 0) return const SizedBox.shrink();
          return Text(
            '$count',
            style: TextStyle(
              fontSize: HrFont.body,
              fontWeight: FontWeight.w600,
              color: isSelected ? selectedColor : colorScheme.onSurfaceVariant,
            ),
          );
        },
      );
    } else if (pendingCount != null) {
      final status = HrStatusColors.of(context);
      iconWidget = StreamBuilder<int>(
        stream: pendingCount,
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          return Badge(
            isLabelVisible: count > 0,
            label: Text(
              '$count',
              style: const TextStyle(
                fontSize: HrFont.labelSmall,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor:
                item.badgeWarning ? status.warning : status.danger,
            textColor: item.badgeWarning ? status.onWarning : status.onDanger,
            child: Icon(
              isSelected ? item.selectedIcon : item.icon,
              size: 20,
              color: iconColor,
            ),
          );
        },
      );
    }

    void open() {
      if (item.index < 0) {
        onOpenProfile();
      } else {
        onItemSelected(item.index);
      }
    }

    if (web) {
      return _webNavDestination(
        item: item,
        isSelected: isSelected,
        colorScheme: colorScheme,
        iconWidget: iconWidget,
        labelColor: labelColor,
        showLabels: showLabels,
        trailing: trailing,
        onTap: open,
      );
    }

    final content = AnimatedContainer(
      duration: AppMotionDurations.short3,
      curve: AppMotionCurves.standardDecelerate,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.symmetric(
        horizontal: showLabels ? 12 : 8,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(HrRadius.card),
      ),
      child: Row(
        mainAxisAlignment: showLabels
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          iconWidget,
          if (showLabels) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: HrFont.body,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: labelColor,
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
        onTap: open,
        borderRadius: BorderRadius.circular(HrRadius.card),
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: showLabels
            ? content
            : _collapsedRailTarget(
                label: item.title,
                selected: isSelected,
                child: content,
              ),
      ),
    );
  }

  /// Web drawer row (48dp) or rail destination (48dp target, 56×32 indicator).
  Widget _webNavDestination({
    required HRSidebarItemData item,
    required bool isSelected,
    required ColorScheme colorScheme,
    required Widget iconWidget,
    required Color labelColor,
    required bool showLabels,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final indicator = BoxDecoration(
      color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(showLabels ? 24 : 16),
    );
    final destination = showLabels
        ? AnimatedContainer(
            duration: AppMotionDurations.short3,
            curve: AppMotionCurves.standardDecelerate,
            height: 48,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: indicator,
            child: Row(
              children: [
                iconWidget,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: HrFont.body,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: labelColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
              ],
            ),
          )
        : SizedBox(
            height: 48,
            width: double.infinity,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotionDurations.short3,
                curve: AppMotionCurves.standardDecelerate,
                width: 56,
                height: 32,
                alignment: Alignment.center,
                decoration: indicator,
                child: iconWidget,
              ),
            ),
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(showLabels ? 24 : 16),
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: showLabels
            ? destination
            : _collapsedRailTarget(
                label: item.title,
                selected: isSelected,
                child: destination,
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
    bool showLabels,
  ) {
    final showProfile = !WebRuntimePolicy.isWeb;
    return Container(
      padding: EdgeInsets.all(showLabels ? 12 : 8),
      child: Column(
        children: [
          if (showProfile) ...[
            if (showLabels)
              InkWell(
                onTap: onOpenProfile,
                borderRadius: BorderRadius.circular(HrRadius.card),
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
                                fontSize: HrFont.body,
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
                                  fontSize: HrFont.labelSmall,
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
          if (showLabels)
            InkWell(
              onTap: onOpenSettings,
              borderRadius: BorderRadius.circular(HrRadius.card),
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
                          fontSize: HrFont.body,
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
            _railIconButton(
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

  /// Collapsed rail row: hover tooltip, and on web a semantics label.
  /// Mobile keeps the tooltip it already had.
  Widget _collapsedRailTarget({
    required String label,
    required bool selected,
    required Widget child,
  }) {
    final web = WebRuntimePolicy.isWeb;
    return Tooltip(
      message: label,
      excludeFromSemantics: web,
      waitDuration: const Duration(milliseconds: 300),
      child: web
          ? Semantics(
              button: true,
              selected: selected,
              label: label,
              child: child,
            )
          : child,
    );
  }

  /// Icon-only rail control. Web adds a semantics label beside the tooltip.
  Widget _railIconButton({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
    ButtonStyle? style,
  }) {
    final button = IconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      style: style,
    );
    if (!WebRuntimePolicy.isWeb) return button;
    return Semantics(button: true, label: tooltip, child: button);
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
/// so the last tools are never hidden behind الإعدادات. The scrollbar is a
/// thin overlay that appears on hover or while scrolling. The selected row
/// is scrolled into view.
class HrSidebarScrollArea extends StatefulWidget {
  final int selectedIndex;
  final List<HrSidebarEntry> entries;
  final EdgeInsets padding;

  const HrSidebarScrollArea({
    super.key,
    required this.selectedIndex,
    required this.entries,
    this.padding = const EdgeInsets.fromLTRB(10, 12, 10, 16),
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
    return HrOverlayScrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        key: const ValueKey('hr_sidebar_scroll'),
        controller: _controller,
        physics: const ClampingScrollPhysics(),
        padding: widget.padding,
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
    );
  }
}
