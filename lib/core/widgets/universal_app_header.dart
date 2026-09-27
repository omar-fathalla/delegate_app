import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/widgets/app_avatar.dart';
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
class UniversalAppHeader extends StatelessWidget implements PreferredSizeWidget {
  final Delegate delegate;
  final String? customTitle;
  final String? customSubtitle;
  final List<Widget>? extraActions;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenuSelected;
  final bool showBackButton;
  final VoidCallback? onBackPressed;

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
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  String _getRoleLabel(BuildContext context, Delegate del) {
    final l10n = AppLocalizations.of(context);
    switch (del.role) {
      case UserRole.accountant:
        return l10n?.accountant ?? 'إدارة الحسابات';
      case UserRole.superAdmin:
        return 'سوبر أدمن';
      case UserRole.organizationAdmin:
        return 'أدمن منظمة';
      case UserRole.admin:
        if (del.position == DelegatePosition.supervisor) {
          return 'مشرف';
        }
        return 'مسؤول شركة';
      case UserRole.technicalSupport:
        return 'دعم فني';
      case UserRole.marketingPromotion:
        return 'ترويج تسويقي';
      case UserRole.marketing:
        return 'تسويق';
      case UserRole.branchesMarketingManager:
        return 'مدير فروع التسويق';
      case UserRole.hr:
        return 'موارد بشرية (HR)';
      case UserRole.delegate:
        if (del.position == DelegatePosition.supervisor) {
          return 'مشرف';
        } else if (del.position == DelegatePosition.promoter) {
          return 'مروج';
        }
        return 'مندوب';
    }
  }

  String _getOrganizationsLabel(Delegate del, Map<String, dynamic>? userData) {
    final orgNames = <String>[];

    if (userData != null) {
      final rawList = userData['organizationNames'] ??
          userData['organizations'] ??
          userData['assignedOrganizations'];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is String && item.trim().isNotEmpty) {
            orgNames.add(item.trim());
          } else if (item is Map &&
              item['name'] is String &&
              (item['name'] as String).trim().isNotEmpty) {
            orgNames.add((item['name'] as String).trim());
          }
        }
      }
    }

    if (orgNames.isEmpty && del.organizationName.isNotEmpty) {
      final parts = del.organizationName
          .split(RegExp(r'[,،•]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      orgNames.addAll(parts);
    }

    if (orgNames.isEmpty && userData != null) {
      final singleOrg = (userData['organizationName'] as String?)?.trim();
      if (singleOrg != null && singleOrg.isNotEmpty) {
        orgNames.add(singleOrg);
      }
    }

    if (orgNames.isEmpty) {
      final comp = (userData?['companyName'] as String?)?.trim() ?? del.companyName.trim();
      if (comp.isNotEmpty) {
        orgNames.add(comp);
      }
    }

    if (orgNames.isEmpty) return '';
    return orgNames.toSet().join(' • ');
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
            final url = doc['documentURL'] as String? ??
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
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null && authUser.uid == del.uid) {
      final authPhoto = authUser.photoURL;
      if (authPhoto != null && authPhoto.trim().isNotEmpty) {
        return authPhoto.trim();
      }
    }

    // 3. تحقق من الصورة في كائن المندوب
    if (del.personalPhotoUrl != null && del.personalPhotoUrl!.trim().isNotEmpty) {
      return del.personalPhotoUrl!.trim();
    }

    // 4. تحقق من قائمة المستندات في كائن المندوب
    final docPhoto = del.documents
        .where((d) =>
            d.documentKey == DocumentKey.personalPhoto &&
            d.documentURL.isNotEmpty)
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

    return AppBar(
      backgroundColor: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 2.0,
      leading: showBackButton
          ? IconButton(
              icon: const BackButtonIcon(),
              onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
            )
          : null,
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
              children: [
                Text(
                  customTitle!,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (customSubtitle != null)
                  Text(
                    customSubtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
            .collection('users')
            .doc(delegate.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final userData = snapshot.data?.data();

          // حل الصورة الحية
          final photoUrl = _resolvePhotoUrl(delegate, userData);

          // حل الاسم
          final rawName = userData?['fullName'] as String? ??
              userData?['name'] as String? ??
              userData?['displayName'] as String? ??
              (delegate.fullName.isNotEmpty
                  ? delegate.fullName
                  : delegate.firstName);
          final displayName = rawName.isNotEmpty ? rawName : 'مستخدم';

          // حل الدور والمنظمة
          final roleLabel = _getRoleLabel(context, delegate);
          final orgsLabel = _getOrganizationsLabel(delegate, userData);

          return Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/user-profile', extra: delegate),
                child: AppAvatar(
                  imageUrl: photoUrl,
                  fallbackText: displayName.isNotEmpty ? displayName[0] : 'U',
                  radius: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push('/user-profile', extra: delegate),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              roleLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          if (orgsLabel.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                orgsLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
      actions: [
        ...?extraActions,
        PopupMenuButton<String>(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'القائمة الرئيسية',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onSelected: onMenuSelected,
          itemBuilder: (_) => menuItems,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
