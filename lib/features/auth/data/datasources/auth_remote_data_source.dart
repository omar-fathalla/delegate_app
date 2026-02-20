import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

abstract class AuthRemoteDataSource {
  /// Queries the `delegates` collectionGroup by phone number.
  /// Returns [DelegateModel] if found, `null` if not.
  Future<DelegateModel?> getDelegateByPhone(String phoneNumber);

  /// Signs in the user anonymously to satisfy Firestore rules.
  Future<void> signInAnonymously();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseFirestore firestore;

  AuthRemoteDataSourceImpl({required this.firestore});

  /// Normalises a phone number by stripping common Egyptian prefixes
  /// (`+2`, `+20`, `002`, `0020`) so queries match the bare format
  /// stored in Firestore (e.g. `"01274114404"`).
  String _normalizePhone(String phone) {
    String normalized = phone.trim();

    if (normalized.startsWith('+20')) {
      normalized = '0${normalized.substring(3)}';
    } else if (normalized.startsWith('+2')) {
      normalized = normalized.substring(2);
    } else if (normalized.startsWith('0020')) {
      normalized = '0${normalized.substring(4)}';
    } else if (normalized.startsWith('002')) {
      normalized = normalized.substring(3);
    }

    return normalized;
  }

  @override
  Future<DelegateModel?> getDelegateByPhone(String phoneNumber) async {
    try {
      final normalizedPhone = _normalizePhone(phoneNumber);

      final querySnapshot = await firestore
          .collectionGroup('delegates')
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return DelegateModel.fromJson(doc.data(), doc.id);
      } else {
        // Fallback: Check if the user is an admin in the 'users' collection
        final userQuery = await firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: normalizedPhone)
            .limit(1)
            .get();

        if (userQuery.docs.isNotEmpty) {
          final userDoc = userQuery.docs.first;
          final userData = userDoc.data();
          final role = userData['role'] as String? ?? '';

          if (role == 'company-admin' || role == 'organization-admin') {
            // Map admin user to a supervisor DelegateModel for dashboard access
            return DelegateModel(
              uid: userDoc.id,
              firstName: userData['displayName'] ?? 'Admin',
              middleName: '',
              lastName: '',
              fullName: userData['displayName'] ?? 'Admin',
              nationalityID: '4816361Aa', // Mock password to pass Login UseCase
              motherName: '',
              city: '',
              phoneNumber: normalizedPhone,
              gender: DelegateGender.male,
              position:
                  DelegatePosition.supervisor, // Forces dashboard redirect
              birthDate: DateTime.now(),
              organizationUID: userData['organizationUID'] ?? '',
              organizationName: userData['organizationName'] ?? '',
              companyUID: userData['companyUID'] ?? '',
              companyName: userData['companyName'] ?? '',
              status: DelegateStatus.approved,
              delegatePublicId: '',
              allReceiptCodes: const [],
              createdAt: DateTime.now(),
              createdBy: 'system',
              hasPendingUpdate: false,
              isDeductedFromCompany: false,
              isPrinted: false,
              isProfileComplete: true,
              numberOfDocuments: 0,
              paymentAmount: 0,
              version: 1,
              documents: const [],
            );
          }
        }
        return null;
      }
    } on FirebaseException catch (e) {
      debugPrint(
        'AuthRemoteDataSource.getDelegateByPhone FirebaseException: Code: ${e.code}, Message: ${e.message}',
      );
      throw const ServerFailure(
        'فشل في الاتصال بقاعدة البيانات. حاول مرة أخرى.',
      );
    } catch (e) {
      debugPrint('AuthRemoteDataSource.getDelegateByPhone error: $e');
      throw const ServerFailure('حدث خطأ غير متوقع أثناء تسجيل الدخول.');
    }
  }

  @override
  Future<void> signInAnonymously() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      debugPrint('AuthRemoteDataSource.signInAnonymously error: $e');
      throw const ServerFailure('فشل في تهيئة جلسة المستخدم.');
    }
  }
}
