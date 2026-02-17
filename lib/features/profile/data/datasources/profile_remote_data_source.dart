import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:flutter/foundation.dart';

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

      // AUTO-FIX: If Org/Comp IDs are missing, create default data
      if (organizationUID == null || companyUID == null) {
        debugPrint(
          'Missing Organization/Company IDs for user $uid. Attempting auto-fix...',
        );

        const defaultOrgId = 'fathalla_market';
        const defaultCompId = 'main_branch';

        // 1. Update User Document
        await firestore.collection('users').doc(uid).update({
          'organizationUID': defaultOrgId,
          'companyUID': defaultCompId,
        });

        // 2. Ensure Organization Exists
        final orgRef = firestore.collection('organizations').doc(defaultOrgId);
        final orgDoc = await orgRef.get();
        if (!orgDoc.exists) {
          await orgRef.set({
            'uid': defaultOrgId,
            'name': 'Fathalla Market',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // 3. Ensure Company Exists
        final compRef = orgRef.collection('companies').doc(defaultCompId);
        final compDoc = await compRef.get();
        if (!compDoc.exists) {
          await compRef.set({
            'uid': defaultCompId,
            'name': 'Main Branch',
            'organizationUID': defaultOrgId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // 4. Update local variables to proceed
        organizationUID = defaultOrgId;
        companyUID = defaultCompId;
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
        debugPrint('Delegate profile not found for $uid. Creating default...');
        // AUTO-FIX: Create Default Delegate Profile
        final defaultDelegateData = {
          'uid': uid,
          'firstName': userData['firstName'] ?? 'Delegate',
          'middleName': '',
          'lastName': '',
          'fullName': userData['fullName'] ?? 'Delegate User',
          'nationalityID': '',
          'motherName': '',
          'city': '',
          'phoneNumber': userData['phoneNumber'] ?? '',
          'gender': 'Male',
          'position': 'Promoter',
          'birthDate': Timestamp.now(),
          'organizationUID': organizationUID,
          'companyUID': companyUID,
          'status': 'Pending',
          'documents': [],
          'createdAt': FieldValue.serverTimestamp(),
        };

        await delegateRef.set(defaultDelegateData);

        // Return the newly created model
        // Note: we can't use fromJson immediate because some fields like timestamps might need fetch
        // But for speed, we construct it manually or re-fetch.
        // Let's re-fetch to be safe and consistent.
        final newDoc = await delegateRef.get();
        if (!newDoc.exists || newDoc.data() == null) {
          throw ServerException('Failed to create default delegate profile');
        }
        return DelegateModel.fromJson(newDoc.data()!, uid);
      }

      final delegateData = delegateDoc.data();
      if (delegateData == null) {
        throw ServerException('Delegate data is empty');
      }

      // 3. Convert to Model
      return DelegateModel.fromJson(delegateData, uid);
    } catch (e) {
      debugPrint('Error in getDelegateProfile: $e');
      if (e is ServerException) rethrow;
      throw ServerException(e.toString());
    }
  }
}
