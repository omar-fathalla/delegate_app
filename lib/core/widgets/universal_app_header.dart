import 'package:delegate_app/core/l10n/display_names.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/session_user_doc_builder.dart';
import 'package:delegate_app/core/widgets/tashil_maestro_dev_semantics.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// هيدر شريط التطبيق الموحد لجميع أدوار المستخدمين التسعة
/// (مندوب، مروج، مشرف، مسؤول شركة، سوبر أدمن، مسؤول منظمة، دعم فني، تسويق، مدير فروع، محاسب)
///
/// يلتزم بالمواصفات:
/// 1. صورة البروفايل المحدثة حياً من فيربيز أو الحرف الأول كـ Fallback
/// 2. اسم المستخدم فوق بخط واضح وعريض
/// 3. شارة نوع الحساب (الدور) والمنظمة/المنظمات تحت الاسم
/// 4. زر قائمة همبرجر موحد (3 شروط) على الطرف المقابل
class UniversalAppHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final Delegate delegate;
  final String? customTitle;
  final String? customSubtitle;
  final List<Widget>? extraActions;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenuSelected;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final FirebaseFirestore? firestore;

  /// إظهار شريحة المنظمة النشطة بجانب الدور (تُخفى في هيدر مشرف/مسؤول الشركة).
  final bool showActiveOrganization;

  /// M3 layout used by the delegate workspace: `leading` opens
  /// [Scaffold.drawer] (start edge, so right in RTL), `actions` hold the
  /// extra actions and the avatar. Other roles keep the popup menu.
  final bool useDrawer;

  const UniversalAppHeader({
    super.key,
    required this.delegate,
    required this.menuItems,
    required this.onMenuSelected,
    this.customTitle,
    this.customSubtitle,
    this.extraActions,
    this.showBackButton = false,
    this.onBackPressed,
    this.firestore,
    this.showActiveOrganization = true,
    this.useDrawer = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  String _getRoleLabel(
    BuildContext context,
    Delegate del, [
    Map<String, dynamic>? userData,
  ]) {
    final l10n = AppLocalizations.of(context);
    final label = roleLabelFor(
      del.role,
      position: del.position,
      rawRole: userData?['role'] as String?,
      accountantLabel: l10n?.accountant,
      marketingPromotionLabel: l10n?.roleMarketingPromotion,
      branchesMarketingManagerLabel: l10n?.roleBranchesMarketingManager,
    );
    return localizeRoleLabel(label, l10n);
  }

  /// Glossary: one role name per locale («مندوب» / Delegate; never «مروج»).
  static String localizeRoleLabel(String label, AppLocalizations? l10n) {
    if (l10n == null) return label;
    switch (label) {
      case 'مندوب':
      case 'مروج':
        return l10n.roleDelegate;
      case 'مشرف الشركة':
      case 'مسؤول الشركة / المشرف':
      case 'مسؤول شركة':
        return l10n.roleCompanyAdmin2;
      case 'مشرف':
        return l10n.roleSupervisor;
      case 'سوبر أدمن':
        return l10n.roleSuperAdmin;
      case 'أدمن منظمة':
        return l10n.roleOrgAdmin;
      case 'دعم فني':
        return l10n.roleTechSupport;
      case 'تسويق':
        return l10n.roleMarketing;
      case 'موارد بشرية (HR)':
        return l10n.roleHr;
    }
    return label;
  }

  /// يحوّل دور المستخدم إلى تسمية عربية قصيرة تظهر تحت الاسم في الهيدر.
  /// Company admin and company supervisor are one UserRole.admin: the label
  /// does not depend on the raw Firestore role string or job-title position.
  @visibleForTesting
  static String roleLabelFor(
    UserRole role, {
    DelegatePosition? position,
    String? rawRole,
    String? accountantLabel,
    String? marketingPromotionLabel,
    String? branchesMarketingManagerLabel,
  }) {
    // rawRole is kept on the API so callers can pass the Firestore string;
    // it must not split company admin vs company supervisor labels.
    rawRole;
    switch (role) {
      case UserRole.accountant:
        return accountantLabel ?? 'إدارة الحسابات';
      case UserRole.superAdmin:
        return 'سوبر أدمن';
      case UserRole.organizationAdmin:
        return 'أدمن منظمة';
      case UserRole.admin:
        return 'مشرف الشركة';
      case UserRole.technicalSupport:
        return 'دعم فني';
      case UserRole.marketingPromotion:
        return marketingPromotionLabel ?? 'تسويق العروض';
      case UserRole.marketing:
        return 'تسويق';
      case UserRole.branchesMarketingManager:
        return branchesMarketingManagerLabel ?? 'مدير تسويق الفروع';
      case UserRole.hr:
        return 'موارد بشرية (HR)';
      case UserRole.delegate:
        if (position == DelegatePosition.supervisor) return 'مشرف';
        if (position == DelegatePosition.promoter) return 'مروج';
        return 'مندوب';
    }
  }

  /// اسم العرض في الهيدر بنفس ترتيب شاشة الملف الشخصي:
  /// fullName من المستند ← اسم الجلسة ← name/displayName من المستند.
  @visibleForTesting
  static String resolveDisplayName(
    Delegate del,
    Map<String, dynamic>? userData,
  ) {
    String? clean(Object? v) {
      final t = (v is String) ? v.trim() : '';
      return t.isEmpty ? null : t;
    }

    return clean(userData?['fullName']) ??
        clean(del.fullName) ??
        clean(del.firstName) ??
        clean(userData?['name']) ??
        clean(userData?['displayName']) ??
        'مستخدم';
  }

  String _formatOrgLabel(String raw) {
    final clean = raw.trim();
    final lower = clean.toLowerCase();
    if (lower.contains('fathalla') ||
        clean.contains('فتح الله') ||
        clean.contains('فتح_الله')) {
      return 'فتح الله ماركت';
    }
    if (lower.contains('gomla') ||
        lower.contains('jomla') ||
        clean.contains('جملة') ||
        clean.contains('جمله')) {
      return 'جملة ماركت';
    }
    if (lower.contains('zahran') || clean.contains('زهران')) {
      return 'زهران ماركت';
    }
    if (lower.contains('carrefour') || clean.contains('كارفور')) {
      return 'كارفور';
    }
    if (lower.contains('beit') || clean.contains('بيت الجملة')) {
      return 'بيت الجملة';
    }
    return clean;
  }

  String _getActiveOrganizationLabel(
    Delegate del,
    Map<String, dynamic>? userData,
  ) {
    // إظهار المنظمة النشطة الحالية فقط في الهيدر العلوي
    if (del.organizationName.trim().isNotEmpty) {
      return _formatOrgLabel(del.organizationName);
    }
    if (userData != null) {
      final singleOrg = (userData['organizationName'] as String?)?.trim();
      if (singleOrg != null && singleOrg.isNotEmpty) {
        return _formatOrgLabel(singleOrg);
      }
    }
    if (del.companyName.trim().isNotEmpty) {
      return del.companyName.trim();
    }
    final comp = (userData?['companyName'] as String?)?.trim();
    if (comp != null && comp.isNotEmpty) {
      return comp;
    }
    return '';
  }

  String? _resolvePhotoUrl(Delegate del, Map<String, dynamic>? userData) {
    // 1. تحقق من بيانات فايرستور المباشرة
    if (userData != null) {
      final p1 = userData['photoURL'] as String?;
      if (p1 != null && p1.trim().isNotEmpty) return p1.trim();
      final p2 = userData['profileImageUrl'] as String?;
      if (p2 != null && p2.trim().isNotEmpty) return p2.trim();
      final p3 = userData['personalPhotoURL'] as String?;
      if (p3 != null && p3.trim().isNotEmpty) return p3.trim();
      final p4 = userData['personalPhotoUrl'] as String?;
      if (p4 != null && p4.trim().isNotEmpty) return p4.trim();
      final p5 = userData['imageUrl'] as String?;
      if (p5 != null && p5.trim().isNotEmpty) return p5.trim();
      final p6 = userData['avatarUrl'] as String?;
      if (p6 != null && p6.trim().isNotEmpty) return p6.trim();

      // فحص مصفوفة المستندات داخل بيانات فايرستور
      final docs = userData['documents'];
      if (docs is List) {
        for (final doc in docs) {
          if (doc is Map &&
              (doc['documentKey'] == 'personalPhoto' ||
                  doc['key'] == 'personalPhoto' ||
                  doc['type'] == 'personalPhoto')) {
            final url =
                doc['documentURL'] as String? ??
                doc['url'] as String? ??
                doc['downloadUrl'] as String?;
            if (url != null && url.trim().isNotEmpty) {
              return url.trim();
            }
          }
        }
      }
    }

    // 2. تحقق من FirebaseAuth currentUser (فقط إذا كان نفس المستخدم صاحب الحساب)
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null && authUser.uid == del.uid) {
        final authPhoto = authUser.photoURL;
        if (authPhoto != null && authPhoto.trim().isNotEmpty) {
          return authPhoto.trim();
        }
      }
    } catch (_) {}

    // 3. تحقق من الصورة في كائن المندوب
    if (del.personalPhotoUrl != null &&
        del.personalPhotoUrl!.trim().isNotEmpty) {
      return del.personalPhotoUrl!.trim();
    }

    // 4. تحقق من قائمة المستندات في كائن المندوب
    final docPhoto = del.documents
        .where(
          (d) =>
              d.documentKey == DocumentKey.personalPhoto &&
              d.documentURL.isNotEmpty,
        )
        .firstOrNull
        ?.documentURL;
    if (docPhoto != null && docPhoto.trim().isNotEmpty) {
      return docPhoto.trim();
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppBar(
      backgroundColor: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 2.0,
      automaticallyImplyLeading: false,
      leading: showBackButton
          ? IconButton(
              icon: const BackButtonIcon(),
              onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
            )
          : useDrawer
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Symbols.menu_rounded),
                tooltip: AppLocalizations.of(ctx)?.mainMenu,
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : null,
      titleSpacing: showBackButton || useDrawer ? 0 : null,
      shape: Border(
        bottom: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      title: customTitle != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  customTitle!,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (customSubtitle != null)
                  Text(
                    customSubtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            )
          : SessionUserDocBuilder(
              uid: delegate.uid,
              subscriptionKey: 'header.title.users.${delegate.uid}',
              firestore: firestore,
              builder: (context, snapshot) {
                final userData = snapshot?.data();

                // حل الصورة الحية
                final photoUrl = _resolvePhotoUrl(delegate, userData);

                // حل الاسم
                final resolvedName = resolveDisplayName(delegate, userData);
                final displayName = nameForLocale(
                  resolvedName,
                  resolvedName,
                  isArabic:
                      Localizations.localeOf(context).languageCode == 'ar',
                );

                final roleLabel = _getRoleLabel(context, delegate, userData);
                final activeOrgName = showActiveOrganization
                    ? localizeChainName(
                        _getActiveOrganizationLabel(delegate, userData),
                        AppLocalizations.of(context),
                      )
                    : '';

                return Row(
                  children: [
                    if (!useDrawer) ...[
                      GestureDetector(
                        onTap: () =>
                            context.push('/user-profile', extra: delegate),
                        child: AppAvatar(
                          imageUrl: photoUrl,
                          fallbackText: displayName.characters.first,
                          radius: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            context.push('/user-profile', extra: delegate),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              style: textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    roleLabel,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (activeOrgName.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: _PulsingActiveOrgChip(
                                      organizationName: activeOrgName,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
      actions: useDrawer
          ? [
              ...?extraActions,
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: IconButton(
                  tooltip: AppLocalizations.of(context)?.profile,
                  onPressed: () =>
                      context.push('/user-profile', extra: delegate),
                  icon: _HeaderAvatar(delegate: delegate, header: this),
                ),
              ),
            ]
          : [
              ...?extraActions,
              tashilMaestroDevSemantics(
                identifier: 'tashil_main_menu_button',
                label: 'القائمة الرئيسية',
                button: true,
                child: PopupMenuButton<String>(
                  icon: const Icon(Symbols.menu_rounded),
                  tooltip:
                      AppLocalizations.of(context)?.mainMenu ??
                      'القائمة الرئيسية',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: onMenuSelected,
                  itemBuilder: (_) => menuItems,
                ),
              ),
              const SizedBox(width: 4),
            ],
    );
  }
}

/// شريحة المنظمة النشطة المضيئة مع أنيميشن إضاءة متوهجة ناعمة تظهر وتختفي (Pulsing Glow)
class _PulsingActiveOrgChip extends StatefulWidget {
  final String organizationName;

  const _PulsingActiveOrgChip({required this.organizationName});

  @override
  State<_PulsingActiveOrgChip> createState() => _PulsingActiveOrgChipState();
}

class _PulsingActiveOrgChipState extends State<_PulsingActiveOrgChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _glowAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        final progress = _glowAnimation.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(
              alpha: 0.75 + 0.25 * progress,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.primary.withValues(
                alpha: 0.35 + 0.45 * progress,
              ),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(
                  alpha: 0.12 + 0.22 * progress,
                ),
                blurRadius: 4.0 + 4.0 * progress,
                spreadRadius: 0.5 * progress,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // نقطة إضاءة خضراء حية نابضة
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(
                    0xFF10B981,
                  ).withValues(alpha: 0.6 + 0.4 * progress),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF10B981,
                      ).withValues(alpha: 0.5 * progress),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4.5),
              Icon(
                Symbols.storefront_rounded,
                size: 12,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.organizationName,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Avatar shown in the app bar actions in drawer mode (live photo from the
/// user document, initial as fallback).
class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({required this.delegate, required this.header});
  final Delegate delegate;
  final UniversalAppHeader header;

  @override
  Widget build(BuildContext context) {
    return SessionUserDocBuilder(
      uid: delegate.uid,
      subscriptionKey: 'header.avatar.users.${delegate.uid}',
      firestore: header.firestore,
      builder: (context, snapshot) {
        final userData = snapshot?.data();
        final name = UniversalAppHeader.resolveDisplayName(delegate, userData);
        return AppAvatar(
          imageUrl: header._resolvePhotoUrl(delegate, userData),
          fallbackText: name.characters.first,
          radius: 16,
        );
      },
    );
  }
}
