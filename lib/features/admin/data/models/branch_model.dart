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
    final location = data['location'] as Map<String, dynamic>? ?? {};

    return BranchModel(
      id: doc.id,
      branchName: data['branchName'] as String? ?? '',
      latitude: (location['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (location['longitude'] as num?)?.toDouble() ?? 0.0,
      geofenceRadius: (data['geofenceRadius'] as num?)?.toDouble() ?? 100.0,
    );
  }

  /// Creates a [BranchModel] from a raw Firestore map (without doc reference).
  /// Supports both nested (`location.latitude`) and top-level (`latitude`) formats
  /// for backwards compatibility with older branch documents.
  factory BranchModel.fromMap(Map<String, dynamic> map, {String id = ''}) {
    final location = map['location'] as Map<String, dynamic>?;

    return BranchModel(
      id: id,
      branchName: map['branchName'] as String? ?? '',
      latitude:
          ((location?['latitude'] ?? map['latitude']) as num?)?.toDouble() ??
          0.0,
      longitude:
          ((location?['longitude'] ?? map['longitude']) as num?)?.toDouble() ??
          0.0,
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
