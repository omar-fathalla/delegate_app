import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/pages/user_profile_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/web/hr_system/hr_western_digits.dart';

/// Header account control for the web HR shell.
///
/// Wide bars show the name beside the avatar. Narrow bars keep the avatar
/// and put the name on the tooltip. The tap opens a compact profile panel
/// instead of the sidebar's navigation menu.
class HrWebAccountButton extends StatelessWidget {
  final Delegate delegate;
  final bool showName;

  const HrWebAccountButton({
    super.key,
    required this.delegate,
    required this.showName,
  });

  String get _name {
    final full = delegate.fullName.trim();
    if (full.isNotEmpty) return full;
    final first = delegate.firstName.trim();
    if (first.isNotEmpty) return first;
    return 'مستخدم';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final name = _name;
    final role = UniversalAppHeader.roleLabelFor(
      delegate.role,
      position: delegate.position,
    );
    final email = delegate.email?.trim() ?? '';
    final phone = delegate.phoneNumber.trim();

    final chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showName) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 148),
            child: Text(
              name,
              key: const ValueKey('hr_web_header_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: AppAvatar(
            imageUrl: delegate.personalPhotoUrl,
            fallbackText: name == 'مستخدم' ? 'H' : name,
            radius: 16,
          ),
        ),
      ],
    );

    return MenuAnchor(
      // The overlay clamps flush to the window, so the anchor shell is
      // transparent and the visible surface sits 8dp inside it.
      reservedPadding: const EdgeInsets.all(8),
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(BorderSide.none),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(side: BorderSide.none),
        ),
      ),
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            key: const ValueKey('hr_web_profile_panel'),
            width: 300,
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              // M3 level-2 lift. Material elevation paints a hard edge in this
              // renderer, so the shadow is a soft blur with no outline.
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.16),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppAvatar(
                              imageUrl: delegate.personalPhotoUrl,
                              fallbackText: name == 'مستخدم' ? 'H' : name,
                              radius: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.secondaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      role,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ContactRow(
                          icon: Icons.mail_outline_rounded,
                          text: email.isEmpty ? '—' : email,
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _ContactRow(
                            key: const ValueKey('hr_web_profile_phone'),
                            icon: Icons.smartphone_rounded,
                            text: hrWesternDigits(phone),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                  MenuItemButton(
                    key: const ValueKey('hr_web_profile_open'),
                    leadingIcon: Icon(Icons.person_rounded, color: cs.primary),
                    onPressed: () =>
                        context.push('/user-profile', extra: delegate),
                    child: Text(l10n.profile),
                  ),
                  MenuItemButton(
                    key: const ValueKey('hr_web_profile_password'),
                    leadingIcon: Icon(
                      Icons.lock_reset_rounded,
                      color: cs.primary,
                    ),
                    onPressed: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          showUserChangePasswordSheet(
                            context,
                            delegate: delegate,
                          );
                        }
                      });
                    },
                    child: Text(l10n.changePassword),
                  ),
                  MenuItemButton(
                    key: const ValueKey('hr_web_profile_logout'),
                    leadingIcon: Icon(
                      Icons.logout_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                    style: ButtonStyle(
                      foregroundColor: WidgetStatePropertyAll(cs.onSurface),
                      iconColor: WidgetStatePropertyAll(cs.onSurfaceVariant),
                    ),
                    onPressed: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          AppLogoutModal.show(context, delegate: delegate);
                        }
                      });
                    },
                    child: Text(l10n.logout),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return Tooltip(
          message: showName ? l10n.profile : name,
          child: Semantics(
            button: true,
            label: name,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('hr_web_header_account'),
                focusColor: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: chip,
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextDirection? textDirection;

  const _ContactRow({
    super.key,
    required this.icon,
    required this.text,
    this.textDirection,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ltr = textDirection == TextDirection.ltr;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: textDirection,
            locale: ltr ? const Locale('en') : null,
            style: TextStyle(fontSize: 13, color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}
