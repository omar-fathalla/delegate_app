import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/captured_photo.dart';

class CapturedPhotoModel extends CapturedPhoto {
  const CapturedPhotoModel({
    required super.uid,
    required super.permissionId,
    required super.organizationUID,
    required super.companyUID,
    super.companyName = '',
    super.companyCode,
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
      companyName: data['companyName']?.toString() ?? '',
      companyCode: data['companyCode'] != null
          ? int.tryParse(data['companyCode'].toString())
          : (data['companyCodeInOrg'] != null
              ? int.tryParse(data['companyCodeInOrg'].toString())
              : null),
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
    final monthKey = '${capturedAt.year}-${capturedAt.month.toString().padLeft(2, '0')}';
    return {
      'permissionId': permissionId,
      'organizationUID': organizationUID,
      'companyUID': companyUID,
      'companyName': companyName,
      if (companyCode != null) 'companyCode': companyCode,
      'branchId': branchId,
      'branchName': branchName,
      'delegateUID': delegateUID,
      'delegateName': delegateName,
      'photoUrl': photoUrl,
      'comment': comment,
      'location': GeoPoint(latitude, longitude),
      'capturedAt': Timestamp.fromDate(capturedAt),
      'monthKey': monthKey,
    };
  }
}
