import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/branch.dart';

class BranchModel extends Branch {
  const BranchModel({
    required super.id,
    required super.branchName,
    required super.latitude,
    required super.longitude,
    required super.geofenceRadius,
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
      lat = (rawLocation['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (rawLocation['longitude'] as num?)?.toDouble() ?? 0.0;
    } else {
      lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
    }

    return BranchModel(
      id: doc.id,
      branchName: data['branchName'] as String? ?? '',
      latitude: lat,
      longitude: lng,
      geofenceRadius: (data['geofenceRadius'] as num?)?.toDouble() ?? 100.0,
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
      lat = (rawLocation['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (rawLocation['longitude'] as num?)?.toDouble() ?? 0.0;
    } else {
      lat = (map['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (map['longitude'] as num?)?.toDouble() ?? 0.0;
    }

    return BranchModel(
      id: id,
      branchName: map['branchName'] as String? ?? '',
      latitude: lat,
      longitude: lng,
      geofenceRadius: (map['geofenceRadius'] as num?)?.toDouble() ?? 100.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'branchName': branchName,
      'location': {'latitude': latitude, 'longitude': longitude},
      'geofenceRadius': geofenceRadius,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
