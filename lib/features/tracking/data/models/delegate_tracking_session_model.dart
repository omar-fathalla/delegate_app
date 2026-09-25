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
    super.isOnline = true,
    super.isMockLocationDetected = false,
    super.offlineBreadcrumbsCount = 0,
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
        .toLowerCase();
    TrackingStatus status;
    if (rawStatus.contains('outside') || rawStatus.contains('breach')) {
      status = TrackingStatus.outsideZone;
    } else if (rawStatus.contains('offline')) {
      status = TrackingStatus.offline;
    } else {
      status = TrackingStatus.insideZone;
    }

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
      isOnline: json['isOnline'] != false,
      isMockLocationDetected: json['isMockLocationDetected'] == true,
      offlineBreadcrumbsCount:
          (json['offlineBreadcrumbsCount'] as num?)?.toInt() ?? 0,
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
      'isOnline': isOnline,
      'isMockLocationDetected': isMockLocationDetected,
      'offlineBreadcrumbsCount': offlineBreadcrumbsCount,
    };
  }
}
