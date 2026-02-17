import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';

abstract class AuthRemoteDataSource {
  Future<DelegateModel?> getDelegateByPhone(String phoneNumber);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseFirestore firestore;

  AuthRemoteDataSourceImpl({required this.firestore});

  @override
  Future<DelegateModel?> getDelegateByPhone(String phoneNumber) async {
    try {
      final querySnapshot = await firestore
          .collectionGroup('delegates')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return DelegateModel.fromJson(doc.data(), doc.id);
      } else {
        return null;
      }
    } catch (e) {
      throw ServerFailure('فشل في الاتصال بالخادم: $e');
    }
  }
}
