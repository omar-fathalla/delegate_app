import 'package:flutter/material.dart';

/// Clear Arabic error + retry for Live Tracking stream failures.
class LiveTrackingLoadError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const LiveTrackingLoadError({
    super.key,
    required this.onRetry,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24.0),
        child: Container(
          key: const Key('live_tracking_load_error'),
          padding: const EdgeInsetsDirectional.all(24.0),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.error.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: colorScheme.error.withValues(alpha: 0.15),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'تعذّر تحميل التتبع المباشر',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'حدث خطأ أثناء جلب بيانات المناديب. تأكد من الاتصال ثم أعد المحاولة.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('live_tracking_retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
