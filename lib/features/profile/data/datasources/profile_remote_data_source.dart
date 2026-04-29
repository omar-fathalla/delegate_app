import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';

abstract class ProfileRemoteDataSource {
  Future<DelegateModel> getDelegateProfile(
    String uid, {
    String? organizationUID,
    String? companyUID,
  });
}

class ProfileRemoteDataSourceImpl implements ProfileRemoteDataSource {
  final FirebaseFirestore firestore;

  ProfileRemoteDataSourceImpl({required this.firestore});

  @override
  Future<DelegateModel> getDelegateProfile(
    String uid, {
    String? organizationUID,
    String? companyUID,
  }) async {
    try {
      String? orgId = organizationUID;
      String? compId = companyUID;

      if (orgId == null || compId == null) {
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

        orgId = userData['organizationUID'] as String?;
        compId = userData['companyUID'] as String?;

        if (orgId == null || compId == null) {
          throw ServerException(
            'User profile incomplete (Missing Org/Company ID). Please contact admin.',
          );
        }
      }

      // 2. Fetch Delegate Data using the constructed path
      final delegateRef = firestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(compId)
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
      if (e is FirebaseException && e.code == 'permission-denied') {
        _healAnonymousSession();
        throw ServerException(
          'ليس لديك صلاحية الوصول (تم تجديد الجلسة، يرجى المحاولة مرة أخرى)',
        );
      }
      throw ServerException(e.toString());
    }
  }

  Future<void> _healAnonymousSession() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser?.isAnonymous == true) {
        await auth.signOut();
        await auth.signInAnonymously();
      } else if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
    } catch (_) {}
  }
}
