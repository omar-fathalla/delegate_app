import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract class AuthRemoteDataSource {
  /// Queries the `delegates` collectionGroup by phone number.
  /// Returns a list of [DelegateModel] matching the phone number.
  /// May contain multiple documents if delegate is registered in multiple orgs.
  Future<List<DelegateModel>> getDelegatesByPhone(String phoneNumber);

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
  Future<List<DelegateModel>> getDelegatesByPhone(String phoneNumber) async {
    try {
      final normalizedPhone = _normalizePhone(phoneNumber);

      // ── Super Admin Login ──────────────────────────────────────────
      if (normalizedPhone == '01508899965') {
        return [
          DelegateModel(
            uid: 'super-admin-login',
            firstName: 'Super Admin',
            middleName: '',
            lastName: '',
            fullName: 'Super Admin',
            nationalityID: '01508899965000',
            motherName: '',
            city: '',
            phoneNumber: normalizedPhone,
            gender: DelegateGender.male,
            position: DelegatePosition.supervisor,
            birthDate: DateTime.now(),
            organizationUID: '',
            organizationName: '',
            companyUID: '',
            companyName: '',
            status: DelegateStatus.approved,
            delegatePublicId: '',
            allReceiptCodes: const [],
            createdAt: DateTime.now(),
            createdBy: 'system_admin',
            hasPendingUpdate: false,
            isDeductedFromCompany: false,
            isPrinted: false,
            isProfileComplete: true,
            numberOfDocuments: 0,
            paymentAmount: 0,
            version: 1,
            documents: const [],
            role: UserRole.superAdmin,
          ),
        ];
      }
      // ──────────────────────────────────────────────────────────────

      final querySnapshot = await firestore
          .collectionGroup('delegates')
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .get();

      final delegates = <DelegateModel>[];
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        delegates.add(DelegateModel.fromJson(data, doc.id));
      }

      // Also check if the user is an admin in the 'users' collection
      // (a phone number can exist in both delegates and users collections)
      try {
        final userQuery = await firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: normalizedPhone)
            .limit(1)
            .get();

        if (userQuery.docs.isNotEmpty) {
          final userDoc = userQuery.docs.first;
          final userData = userDoc.data();
          final userRole = userData['role'] as String? ?? '';
          if (userRole == 'company-admin' ||
              userRole == 'organization-admin' ||
              userRole == 'Supervisor') {
            // Get admin email to use for Firebase Auth verification
            final adminEmail = userData['email'] as String? ?? '';

            // Use a special marker in nationalityID to indicate Firebase Auth login
            // The actual password verification will happen via Firebase Auth in the login usecase
            delegates.add(
              DelegateModel(
                uid: userDoc.id,
                firstName: userData['displayName'] ?? 'Admin',
                middleName: '',
                lastName: '',
                fullName: userData['displayName'] ?? 'Admin',
                nationalityID: '__firebase_auth__:$adminEmail',
                motherName: '',
                city: '',
                phoneNumber: normalizedPhone,
                gender: DelegateGender.male,
                position: DelegatePosition.supervisor,
                birthDate: DateTime.now(),
                organizationUID: userData['organizationUID'] ?? '',
                organizationName: userData['organizationName'] ?? '',
                companyUID: userData['companyUID'] ?? '',
                companyName: userData['companyName'] ?? '',
                status: DelegateStatus.approved,
                delegatePublicId: '',
                allReceiptCodes: const [],
                createdAt: DateTime.now(),
                createdBy: 'system_admin',
                hasPendingUpdate: false,
                isDeductedFromCompany: false,
                isPrinted: false,
                isProfileComplete: true,
                numberOfDocuments: 0,
                paymentAmount: 0,
                version: 1,
                documents: const [],
                role: UserRole.admin,
              ),
            );
          }
        }
      } on FirebaseException catch (_) {
        // Query failed — continue with delegates only.
      }

      return delegates;
    } on FirebaseException catch (_) {
      throw const ServerFailure(
        'فشل في الاتصال بقاعدة البيانات. حاول مرة أخرى.',
      );
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع أثناء تسجيل الدخول.');
    }
  }

  @override
  Future<void> signInAnonymously() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {
      throw const ServerFailure('فشل في تهيئة جلسة المستخدم.');
    }
  }
}
