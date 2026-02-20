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

  Map<String, dynamic> toMap() {
    return {
      'branchName': branchName,
      'location': {'latitude': latitude, 'longitude': longitude},
      'geofenceRadius': geofenceRadius,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
