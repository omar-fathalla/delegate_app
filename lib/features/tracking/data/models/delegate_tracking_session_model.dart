import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/delegate_tracking_session.dart';

class DelegateTrackingSessionModel extends DelegateTrackingSession {
  const DelegateTrackingSessionModel({
    required super.delegateId,
    required super.delegateName,
    required super.delegatePhone,
    required super.companyId,
    required super.organizationId,
    required super.branchId,
    required super.branchName,
    required super.branchLat,
    required super.branchLng,
    required super.geofenceRadius,
    required super.isTrackingEnabled,
    required super.currentStatus,
    required super.currentDistanceMeters,
    super.lastLatitude,
    super.lastLongitude,
    required super.lastUpdated,
    super.lastBreachAt,
    super.firstExitedAt,
    super.checkInTime,
    super.checkOutTime,
    super.isOnline = true,
    super.isMockLocationDetected = false,
    super.offlineBreadcrumbsCount = 0,
    super.speed,
    super.batteryLevel,
    super.isMoving,
    super.avatarUrl,
  });

  factory DelegateTrackingSessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return DelegateTrackingSessionModel.fromJson(data, doc.id);
  }

  factory DelegateTrackingSessionModel.fromJson(
      Map<String, dynamic> json, String docId) {
    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? fallback;
      return fallback;
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawStatus = (json['currentStatus'] ?? json['status'] ?? 'inside')
        .toString()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    TrackingStatus status;
    if (rawStatus.contains('checked_out') ||
        rawStatus == 'checkout' ||
        rawStatus == 'checkedout') {
      status = TrackingStatus.checkedOut;
    } else if (rawStatus.contains('outside') || rawStatus.contains('breach')) {
      status = TrackingStatus.outsideZone;
    } else if (rawStatus.contains('offline')) {
      status = TrackingStatus.offline;
    } else if (rawStatus.contains('inside')) {
      status = TrackingStatus.insideZone;
    } else {
      // Unknown statuses must not silently look like "inside".
      status = TrackingStatus.offline;
    }

    final speedVal = json['speed'];
    final double? speed = speedVal is num ? speedVal.toDouble() : null;

    final batteryVal = json['batteryLevel'] ?? json['battery'];
    final int? batteryLevel = batteryVal is num ? batteryVal.toInt() : null;

    final isMovingVal = json['isMoving'];
    final bool? isMoving = isMovingVal is bool
        ? isMovingVal
        : (isMovingVal is String
            ? (isMovingVal.toLowerCase() == 'true' || isMovingVal == '1')
            : null);

    final avatarUrlVal = (json['avatarUrl'] ??
            json['photoURL'] ??
            json['photoUrl'] ??
            json['profileImageUrl'] ??
            json['personalPhotoURL'] ??
            json['personalPhotoUrl'] ??
            json['imageUrl'])
        ?.toString()
        .trim();
    final avatarUrl = (avatarUrlVal != null && avatarUrlVal.isNotEmpty)
        ? avatarUrlVal
        : null;

    return DelegateTrackingSessionModel(
      delegateId: json['delegateId']?.toString() ?? docId,
      delegateName: json['delegateName']?.toString() ??
          json['name']?.toString() ??
          'مندوب غير محدد',
      delegatePhone: json['delegatePhone']?.toString() ??
          json['phone']?.toString() ??
          '',
      companyId: json['companyId']?.toString() ??
          json['companyUID']?.toString() ??
          '',
      organizationId: json['organizationId']?.toString() ??
          json['organizationUID']?.toString() ??
          '',
      branchId: json['branchId']?.toString() ?? '',
      branchName: json['branchName']?.toString() ?? 'فرع غير محدد',
      branchLat: (json['branchLat'] as num?)?.toDouble() ?? 0.0,
      branchLng: (json['branchLng'] as num?)?.toDouble() ?? 0.0,
      geofenceRadius: (json['geofenceRadius'] as num?)?.toDouble() ?? 100.0,
      isTrackingEnabled: json['isTrackingEnabled'] == true,
      currentStatus: status,
      currentDistanceMeters:
          (json['currentDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      lastLatitude: (json['lastLatitude'] as num?)?.toDouble(),
      lastLongitude: (json['lastLongitude'] as num?)?.toDouble(),
      lastUpdated: parseDate(json['lastUpdated'], DateTime.now()),
      lastBreachAt: parseNullableDate(json['lastBreachAt']),
      firstExitedAt: parseNullableDate(json['firstExitedAt']),
      checkInTime: parseNullableDate(json['checkInTime']),
      checkOutTime: parseNullableDate(json['checkOutTime']),
      isOnline: json['isOnline'] != false,
      isMockLocationDetected: json['isMockLocationDetected'] == true,
      offlineBreadcrumbsCount:
          (json['offlineBreadcrumbsCount'] as num?)?.toInt() ?? 0,
      speed: speed,
      batteryLevel: batteryLevel,
      isMoving: isMoving,
      avatarUrl: avatarUrl,
    );
  }

  Map<String, dynamic> toJson() {
    String statusStr;
    switch (currentStatus) {
      case TrackingStatus.outsideZone:
        statusStr = 'outside';
        break;
      case TrackingStatus.offline:
        statusStr = 'offline';
        break;
      case TrackingStatus.checkedOut:
        statusStr = 'checked_out';
        break;
      case TrackingStatus.insideZone:
        statusStr = 'inside';
        break;
    }

    return {
      'delegateId': delegateId,
      'delegateName': delegateName,
      'delegatePhone': delegatePhone,
      'companyId': companyId,
      'organizationId': organizationId,
      'branchId': branchId,
      'branchName': branchName,
      'branchLat': branchLat,
      'branchLng': branchLng,
      'geofenceRadius': geofenceRadius,
      'isTrackingEnabled': isTrackingEnabled,
      'currentStatus': statusStr,
      'currentDistanceMeters': currentDistanceMeters,
      if (lastLatitude != null) 'lastLatitude': lastLatitude,
      if (lastLongitude != null) 'lastLongitude': lastLongitude,
      'lastUpdated': FieldValue.serverTimestamp(),
      if (lastBreachAt != null)
        'lastBreachAt': Timestamp.fromDate(lastBreachAt!),
      if (firstExitedAt != null)
        'firstExitedAt': Timestamp.fromDate(firstExitedAt!),
      if (checkInTime != null)
        'checkInTime': Timestamp.fromDate(checkInTime!),
      if (checkOutTime != null)
        'checkOutTime': Timestamp.fromDate(checkOutTime!),
      'isOnline': isOnline,
      'isMockLocationDetected': isMockLocationDetected,
      'offlineBreadcrumbsCount': offlineBreadcrumbsCount,
      if (speed != null) 'speed': speed,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
      if (isMoving != null) 'isMoving': isMoving,
      if (avatarUrl != null && avatarUrl!.isNotEmpty) 'avatarUrl': avatarUrl,
    };
  }
}
