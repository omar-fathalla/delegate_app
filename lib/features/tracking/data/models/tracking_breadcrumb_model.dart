import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/tracking_breadcrumb.dart';

class TrackingBreadcrumbModel extends TrackingBreadcrumb {
  const TrackingBreadcrumbModel({
    required super.id,
    required super.latitude,
    required super.longitude,
    required super.timestamp,
    super.speed = 0.0,
    super.batteryLevel,
    super.distanceMeters = 0.0,
    super.isInside = true,
  });

  factory TrackingBreadcrumbModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return TrackingBreadcrumbModel.fromJson(doc.data() ?? {}, doc.id);
  }

  factory TrackingBreadcrumbModel.fromJson(
    Map<String, dynamic> json, [
    String id = '',
  ]) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    final batteryVal = json['batteryLevel'] ?? json['battery'];
    final int? batteryLevel = batteryVal is num ? batteryVal.toInt() : null;

    final speedVal = json['speed'];
    final double speed = speedVal is num ? speedVal.toDouble() : 0.0;

    final distVal = json['distanceMeters'] ?? json['distance'];
    final double distanceMeters = distVal is num ? distVal.toDouble() : 0.0;

    return TrackingBreadcrumbModel(
      id: json['id']?.toString() ?? id,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: parseDate(json['timestamp']),
      speed: speed,
      batteryLevel: batteryLevel,
      distanceMeters: distanceMeters,
      isInside: json['isInside'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': Timestamp.fromDate(timestamp),
      'speed': speed,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
      'distanceMeters': distanceMeters,
      'isInside': isInside,
    };
  }
}
