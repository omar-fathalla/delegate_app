import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/core/widgets/universal_app_header.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/pages/user_profile_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// Header account control for the web HR shell.
///
/// Wide bars show the name with the role chip under it, beside the avatar.
/// Narrow bars keep the avatar and put the name on the tooltip. The tap
/// opens a compact profile panel instead of the sidebar's navigation menu.
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

    final isSupervisor = delegate.role == UserRole.admin;
    final textTheme = Theme.of(context).textTheme;
    final chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showName) ...[
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 148),
                child: Text(
                  name,
                  key: const ValueKey('hr_web_header_name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                key: const ValueKey('hr_web_header_role_chip'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSupervisor
                          ? Icons.supervisor_account_rounded
                          : Icons.badge_rounded,
                      size: 14,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isSupervisor ? 'مشرف الشركة' : 'HR',
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        SizedBox(
          key: const ValueKey('hr_web_profile_panel'),
          width: 300,
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
                    const SizedBox(height: 6),
                    _ContactRow(
                      icon: Icons.smartphone_rounded,
                      text: phone.isEmpty ? '—' : phone,
                    ),
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
                onPressed: () => context.push('/user-profile', extra: delegate),
                child: Text(l10n.profile),
              ),
              MenuItemButton(
                key: const ValueKey('hr_web_profile_password'),
                leadingIcon: Icon(Icons.lock_reset_rounded, color: cs.primary),
                onPressed: () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                      showUserChangePasswordSheet(context, delegate: delegate);
                    }
                  });
                },
                child: Text(l10n.changePassword),
              ),
              MenuItemButton(
                key: const ValueKey('hr_web_profile_logout'),
                leadingIcon: Icon(Icons.logout_rounded, color: cs.error),
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(cs.error),
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

  const _ContactRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}
