import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';

abstract class ProfileRemoteDataSource {
  Future<DelegateModel> getDelegateProfile(String uid);
}

class ProfileRemoteDataSourceImpl implements ProfileRemoteDataSource {
  final FirebaseFirestore firestore;

  ProfileRemoteDataSourceImpl({required this.firestore});

  @override
  Future<DelegateModel> getDelegateProfile(String uid) async {
    try {
      // 1. Fetch User Data to get Org/Comp IDs
      final userDoc = await firestore.collection('users').doc(uid).get();

      if (!userDoc.exists) {
        throw ServerException('User not found');
      }

      final userData = userDoc.data();
      if (userData == null) {
        throw ServerException('User data is empty');
      }

      final String? role = userData['role'];

      if (role != 'delegate') {
        throw ServerException('User is not a delegate');
      }

      String? organizationUID = userData['organizationUID'];
      String? companyUID = userData['companyUID'];

      if (organizationUID == null || companyUID == null) {
        throw ServerException(
          'User profile incomplete (Missing Org/Company ID). Please contact admin.',
        );
      }

      // 2. Fetch Delegate Data using the constructed path
      final delegateRef = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('delegates')
          .doc(uid);

      final delegateDoc = await delegateRef.get();

      if (!delegateDoc.exists) {
        throw ServerException(
          'Delegate profile not found in Organization records.',
        );
      }

      final delegateData = delegateDoc.data();
      if (delegateData == null) {
        throw ServerException('Delegate data is empty');
      }

      // 3. Convert to Model
      return DelegateModel.fromJson(delegateData, uid);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(e.toString());
    }
  }
}
