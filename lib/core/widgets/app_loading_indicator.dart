import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

enum AppLoadingStyle {
  threeArchedCircle,
  staggeredDotsWave,
  inkDrop,
  horizontalRotatingDots,
  waveDots,
}

/// A modern Material Design 3 animated loading indicator widget
class AppLoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;
  final AppLoadingStyle style;
  final String? label;

  const AppLoadingIndicator({
    super.key,
    this.size = 36.0,
    this.color,
    this.style = AppLoadingStyle.threeArchedCircle,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    Widget animationWidget;
    switch (style) {
      case AppLoadingStyle.threeArchedCircle:
        animationWidget = LoadingAnimationWidget.threeArchedCircle(
          color: effectiveColor,
          size: size,
        );
        break;
      case AppLoadingStyle.staggeredDotsWave:
        animationWidget = LoadingAnimationWidget.staggeredDotsWave(
          color: effectiveColor,
          size: size,
        );
        break;
      case AppLoadingStyle.inkDrop:
        animationWidget = LoadingAnimationWidget.inkDrop(
          color: effectiveColor,
          size: size,
        );
        break;
      case AppLoadingStyle.horizontalRotatingDots:
        animationWidget = LoadingAnimationWidget.horizontalRotatingDots(
          color: effectiveColor,
          size: size,
        );
        break;
      case AppLoadingStyle.waveDots:
        animationWidget = LoadingAnimationWidget.waveDots(
          color: effectiveColor,
          size: size,
        );
        break;
    }

    if (label == null || label!.isEmpty) {
      return animationWidget;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        animationWidget,
        const SizedBox(height: 12),
        Text(
          label!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Material Design 3 Download & Sync Progress Bar Component
class AppDownloadProgressIndicator extends StatelessWidget {
  final double? progress; // 0.0 to 1.0 or null for indeterminate
  final String title;
  final String? subtitle;
  final VoidCallback? onCancel;

  const AppDownloadProgressIndicator({
    super.key,
    this.progress,
    required this.title,
    this.subtitle,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LoadingAnimationWidget.threeArchedCircle(
                color: colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (progress != null)
                Text(
                  '${(progress! * 100).toInt()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colorScheme.primary,
                  ),
                ),
              if (onCancel != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
