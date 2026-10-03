import 'package:equatable/equatable.dart';

/// تمثل نقطة مسار زمنية (Waypoint / Breadcrumb) لتحرك المندوب الميداني
class TrackingBreadcrumb extends Equatable {
  final String id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double speed;
  final int? batteryLevel;
  final double distanceMeters;
  final bool isInside;

  const TrackingBreadcrumb({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speed = 0.0,
    this.batteryLevel,
    this.distanceMeters = 0.0,
    this.isInside = true,
  });

  @override
  List<Object?> get props => [
        id,
        latitude,
        longitude,
        timestamp,
        speed,
        batteryLevel,
        distanceMeters,
        isInside,
      ];
}
