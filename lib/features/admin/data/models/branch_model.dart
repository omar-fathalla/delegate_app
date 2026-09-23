import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/branch.dart';

class BranchModel extends Branch {
  const BranchModel({
    required super.id,
    required super.branchName,
    required super.latitude,
    required super.longitude,
    required super.geofenceRadius,
    super.organizationUID,
    super.organizationName,
  });

  factory BranchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final dynamic rawLocation = data['location'];
    
    double lat = 0.0;
    double lng = 0.0;

    if (rawLocation is GeoPoint) {
      lat = rawLocation.latitude;
      lng = rawLocation.longitude;
    } else if (rawLocation is Map) {
      lat = (rawLocation['latitude'] as num?)?.toDouble() ??
          (rawLocation['lat'] as num?)?.toDouble() ??
          0.0;
      lng = (rawLocation['longitude'] as num?)?.toDouble() ??
          (rawLocation['lng'] as num?)?.toDouble() ??
          0.0;
    } else {
      lat = (data['latitude'] as num?)?.toDouble() ??
          (data['lat'] as num?)?.toDouble() ??
          0.0;
      lng = (data['longitude'] as num?)?.toDouble() ??
          (data['lng'] as num?)?.toDouble() ??
          0.0;
    }

    final name = data['branchName'] as String? ??
        data['name'] as String? ??
        data['title'] as String? ??
        data['branch_name'] as String? ??
        '';

    final radius = (data['geofenceRadius'] as num?)?.toDouble() ??
        (data['radius'] as num?)?.toDouble() ??
        (data['geofence_radius'] as num?)?.toDouble() ??
        100.0;

    final orgUID = data['organizationUID'] as String? ??
        data['organizationId'] as String? ??
        data['orgId'] as String? ??
        data['organization_uid'] as String?;
    final orgName = data['organizationName'] as String? ??
        data['orgName'] as String? ??
        data['organization_name'] as String?;

    return BranchModel(
      id: doc.id,
      branchName: name,
      latitude: lat,
      longitude: lng,
      geofenceRadius: radius,
      organizationUID: orgUID,
      organizationName: orgName,
    );
  }

  /// Creates a [BranchModel] from a raw Firestore map (without doc reference).
  /// Supports both nested (`location.latitude`) and top-level (`latitude`) formats
  /// for backwards compatibility with older branch documents.
  factory BranchModel.fromMap(Map<String, dynamic> map, {String id = ''}) {
    final dynamic rawLocation = map['location'];
    
    double lat = 0.0;
    double lng = 0.0;

    if (rawLocation is GeoPoint) {
      lat = rawLocation.latitude;
      lng = rawLocation.longitude;
    } else if (rawLocation is Map) {
      lat = (rawLocation['latitude'] as num?)?.toDouble() ??
          (rawLocation['lat'] as num?)?.toDouble() ??
          0.0;
      lng = (rawLocation['longitude'] as num?)?.toDouble() ??
          (rawLocation['lng'] as num?)?.toDouble() ??
          0.0;
    } else {
      lat = (map['latitude'] as num?)?.toDouble() ??
          (map['lat'] as num?)?.toDouble() ??
          0.0;
      lng = (map['longitude'] as num?)?.toDouble() ??
          (map['lng'] as num?)?.toDouble() ??
          0.0;
    }

    final name = map['branchName'] as String? ??
        map['name'] as String? ??
        map['title'] as String? ??
        map['branch_name'] as String? ??
        '';

    final radius = (map['geofenceRadius'] as num?)?.toDouble() ??
        (map['radius'] as num?)?.toDouble() ??
        (map['geofence_radius'] as num?)?.toDouble() ??
        100.0;

    final orgUID = map['organizationUID'] as String? ??
        map['organizationId'] as String? ??
        map['orgId'] as String? ??
        map['organization_uid'] as String?;
    final orgName = map['organizationName'] as String? ??
        map['orgName'] as String? ??
        map['organization_name'] as String?;

    return BranchModel(
      id: id,
      branchName: name,
      latitude: lat,
      longitude: lng,
      geofenceRadius: radius,
      organizationUID: orgUID,
      organizationName: orgName,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'branchName': branchName,
      'location': {'latitude': latitude, 'longitude': longitude},
      'geofenceRadius': geofenceRadius,
      if (organizationUID != null && organizationUID!.isNotEmpty)
        'organizationUID': organizationUID,
      if (organizationName != null && organizationName!.isNotEmpty)
        'organizationName': organizationName,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'branchName': branchName,
      'location': {'latitude': latitude, 'longitude': longitude},
      'geofenceRadius': geofenceRadius,
      if (organizationUID != null && organizationUID!.isNotEmpty)
        'organizationUID': organizationUID,
      if (organizationName != null && organizationName!.isNotEmpty)
        'organizationName': organizationName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
