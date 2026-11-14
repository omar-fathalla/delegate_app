import 'package:flutter/material.dart';

import '../entities/delegate_tracking_session.dart';

/// Arabic UI presentation for geofence / presence status on Live Tracking.
class TrackingGeofenceStatus {
  const TrackingGeofenceStatus({
    required this.title,
    required this.color,
    required this.backgroundColor,
    required this.icon,
  });

  final String title;
  final Color color;
  final Color backgroundColor;
  final IconData icon;

  static TrackingGeofenceStatus resolve(
    DelegateTrackingSession session,
    ColorScheme colorScheme,
  ) {
    switch (session.currentStatus) {
      case TrackingStatus.suspended:
        return TrackingGeofenceStatus(
          title: 'موقوف',
          color: colorScheme.error,
          backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.35),
          icon: Icons.block_rounded,
        );
      case TrackingStatus.forgotSignature:
        return TrackingGeofenceStatus(
          title: 'نسيان توقيع',
          color: const Color(0xFFB8860B),
          backgroundColor: const Color(0xFFB8860B).withValues(alpha: 0.12),
          icon: Icons.edit_off_rounded,
        );
      case TrackingStatus.checkedOut:
        return TrackingGeofenceStatus(
          title: 'منصرف',
          color: colorScheme.outline,
          backgroundColor:
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          icon: Icons.logout_rounded,
        );
      case TrackingStatus.offline:
        return TrackingGeofenceStatus(
          title: 'غير متصل',
          color: const Color(0xFF757575),
          backgroundColor:
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          icon: Icons.cloud_off_rounded,
        );
      case TrackingStatus.outsideZone:
        if (session.isInGracePeriod) {
          return TrackingGeofenceStatus(
            title: 'سماح (${session.remainingGraceSeconds}ث)',
            color: const Color(0xFFC65102),
            backgroundColor: const Color(0xFFC65102).withValues(alpha: 0.1),
            icon: Icons.hourglass_top_rounded,
          );
        }
        final excess =
            (session.currentDistanceMeters - session.geofenceRadius).toInt();
        return TrackingGeofenceStatus(
          title: 'خارج (+$excessم)',
          color: const Color(0xFFC65102),
          backgroundColor: const Color(0xFFC65102).withValues(alpha: 0.1),
          icon: Icons.warning_amber_rounded,
        );
      case TrackingStatus.insideZone:
        return TrackingGeofenceStatus(
          title: 'داخل (${session.currentDistanceMeters.toInt()}م)',
          color: const Color(0xFF2E7D32),
          backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.1),
          icon: Icons.check_circle_rounded,
        );
    }
  }
}