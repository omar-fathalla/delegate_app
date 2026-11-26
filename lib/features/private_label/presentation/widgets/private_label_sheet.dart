import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:material_ui/material_ui.dart';

/// Viewport width above which sheets become centered dialogs (web/desktop).
const double kPrivateLabelDesktopBreakpoint = 768;

/// Layout info handed to sheet builders.
class PrivateLabelSheetLayout {
  /// True on mobile (modal bottom sheet), false on desktop (dialog).
  final bool isSheet;

  /// True when the container has a fixed height (content should fill it).
  final bool expand;

  const PrivateLabelSheetLayout({required this.isSheet, required this.expand});
}

/// Mobile: M3 modal bottom sheet (drag handle, 28dp top radius, keyboard-aware).
/// Desktop/web (> 768dp): centered M3 dialog (max width 540dp, 24dp radius).
///
/// Pass [heightFactor] = null for small confirmation sheets that fit content.
Future<T?> showPrivateLabelSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, PrivateLabelSheetLayout layout) builder,
  double? heightFactor = 0.82,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDesktop = MediaQuery.sizeOf(context).width > kPrivateLabelDesktopBreakpoint;
  final reduceMotion = MediaQuery.of(context).disableAnimations;

  if (isDesktop) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: colorScheme.scrim.withValues(alpha: 0.32),
      transitionDuration: reduceMotion ? Duration.zero : AppMotionDurations.medium1,
      // Exit < Enter (M3 motion): 150ms vs 250ms.
      transitionBuilder: (context, animation, secondary, child) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: AppMotionCurves.standardDefaultEffects,
          reverseCurve: AppMotionCurves.standardAccelerate,
        );
        final scale = CurvedAnimation(
          parent: animation,
          curve: AppMotionCurves.emphasizedDecelerate,
          reverseCurve: AppMotionCurves.emphasizedAccelerate,
        );
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(scale),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, _, _) {
        final size = MediaQuery.sizeOf(dialogContext);
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 540,
                maxHeight: size.height * 0.88,
              ),
              child: Material(
                color: colorScheme.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: builder(
                  dialogContext,
                  const PrivateLabelSheetLayout(isSheet: false, expand: false),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: reduceMotion
        ? AnimationStyle.noAnimation
        : AnimationStyle(
            duration: AppMotionDurations.medium4,
            reverseDuration: AppMotionDurations.short4,
          ),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final content = builder(
        sheetContext,
        PrivateLabelSheetLayout(isSheet: true, expand: heightFactor != null),
      );
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: heightFactor == null
            ? content
            : SizedBox(height: media.size.height * heightFactor, child: content),
      );
    },
  );
}

/// Standard frame: drag handle (mobile), header, scrollable body, bottom actions.
class PrivateLabelSheetFrame extends StatelessWidget {
  final PrivateLabelSheetLayout layout;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? actions;
  final Widget? headerTrailing;

  const PrivateLabelSheetFrame({
    super.key,
    required this.layout,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final body = SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 16),
      child: child,
    );

    return Column(
      mainAxisSize: layout.expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (layout.isSheet)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(20, layout.isSheet ? 8 : 20, 12, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?headerTrailing,
            ],
          ),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        if (layout.expand) Expanded(child: body) else Flexible(child: body),
        if (actions != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
            child: actions,
          ),
      ],
    );
  }
}

/// Connected dual-button group (height 48, radius 24, vertical divider).
class PrivateLabelConnectedActions extends StatelessWidget {
  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback? onSecondary;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final bool isLoading;

  /// Optional override (e.g. `colorScheme.error` for destructive actions).
  final Color? primaryColor;
  final Color? onPrimaryColor;

  const PrivateLabelConnectedActions({
    super.key,
    this.secondaryLabel = 'إلغاء',
    this.secondaryIcon = Icons.close_rounded,
    this.onSecondary,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.isLoading = false,
    this.primaryColor,
    this.onPrimaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onPrimary != null && !isLoading;
    final fill = primaryColor ?? colorScheme.primary;
    final onFill = onPrimaryColor ?? colorScheme.onPrimary;
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.6);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: isLoading ? null : (onSecondary ?? () => Navigator.of(context).maybePop()),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(secondaryIcon, size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      secondaryLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1.2, height: 28, color: borderColor),
          Expanded(
            flex: 3,
            child: AnimatedContainer(
              duration: AppMotionDurations.short4,
              curve: AppMotionCurves.standardDefaultEffects,
              color: enabled ? fill : fill.withValues(alpha: 0.38),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: enabled ? onPrimary : null,
                  child: Center(
                    child: isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: onFill),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(primaryIcon, size: 18, color: onFill),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  primaryLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: onFill,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card/banner with a 3.5dp status line on the start edge (RTL-aware).
///
/// Uses a clipped Row instead of a non-uniform `Border` + `borderRadius`,
/// which Flutter does not allow.
class PrivateLabelAccentContainer extends StatelessWidget {
  final Color accent;
  final Widget child;
  final Color? background;
  final double radius;
  final bool outlined;
  final EdgeInsetsGeometry padding;

  const PrivateLabelAccentContainer({
    super.key,
    required this.accent,
    required this.child,
    this.background,
    this.radius = 14,
    this.outlined = false,
    this.padding = const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: background ?? cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: outlined
            ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.7))
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3.5, color: accent),
            Expanded(child: Padding(padding: padding, child: child)),
          ],
        ),
      ),
    );
  }
}

/// Small status pill (12dp radius) — the only place semantic colors are used.
class PrivateLabelStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const PrivateLabelStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
