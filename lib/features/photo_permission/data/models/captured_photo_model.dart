import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/captured_photo.dart';

class CapturedPhotoModel extends CapturedPhoto {
  const CapturedPhotoModel({
    required super.uid,
    required super.permissionId,
    required super.organizationUID,
    required super.companyUID,
    required super.branchId,
    required super.branchName,
    required super.delegateUID,
    required super.delegateName,
    required super.photoUrl,
    required super.comment,
    required super.latitude,
    required super.longitude,
    required super.capturedAt,
  });

  factory CapturedPhotoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final geoPoint = data['location'] as GeoPoint?;
    final timestamp = data['capturedAt'] as Timestamp?;

    return CapturedPhotoModel(
      uid: doc.id,
      permissionId: data['permissionId']?.toString() ?? '',
      organizationUID: data['organizationUID']?.toString() ?? '',
      companyUID: data['companyUID']?.toString() ?? '',
      branchId: data['branchId']?.toString() ?? '',
      branchName: data['branchName']?.toString() ?? '',
      delegateUID: data['delegateUID']?.toString() ?? '',
      delegateName: data['delegateName']?.toString() ?? '',
      photoUrl: data['photoUrl']?.toString() ?? '',
      comment: data['comment']?.toString() ?? '',
      latitude: geoPoint?.latitude ?? 0.0,
      longitude: geoPoint?.longitude ?? 0.0,
      capturedAt: timestamp?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'permissionId': permissionId,
      'organizationUID': organizationUID,
      'companyUID': companyUID,
      'branchId': branchId,
      'branchName': branchName,
      'delegateUID': delegateUID,
      'delegateName': delegateName,
      'photoUrl': photoUrl,
      'comment': comment,
      'location': GeoPoint(latitude, longitude),
      'capturedAt': Timestamp.fromDate(capturedAt),
    };
  }
}
