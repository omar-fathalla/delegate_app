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

  /// Verifies admin password using Firebase Authentication
  Future<bool> verifyAdminPassword(String email, String password);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseAuth firebaseAuth;

  AuthRemoteDataSourceImpl({
    required this.firestore,
    required this.firebaseAuth,
  });

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
        // Sign in anonymously to satisfy Firestore rules
        await signInAnonymously();

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

      // Sign in anonymously first to query Firestore
      // (will be replaced by admin auth if admin is found)
      await signInAnonymously();

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
              userRole == 'Supervisor' ||
              userRole == 'marketing') {
            // Get admin email from Firestore
            final adminEmail = userData['email'] as String? ?? '';

            // Admin/Marketing login: mark with special flag for Firebase Auth verification
            delegates.add(
              DelegateModel(
                uid: userDoc.id,
                firstName: userData['displayName'] ?? 'User',
                middleName: '',
                lastName: '',
                fullName: userData['displayName'] ?? 'User',
                nationalityID:
                    '__firebase_auth__:$adminEmail', // Mark for Firebase Auth verification
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
                role: userRole == 'marketing'
                    ? UserRole.marketing
                    : UserRole.admin,
              ),
            );
          }
        }
      } on FirebaseException catch (_) {
        // Query failed — continue with delegates only.
      }

      return delegates;
    } on FirebaseException catch (e) {
      throw ServerFailure(
        'فشل في الاتصال بقاعدة البيانات. حاول مرة أخرى. (${e.code})',
      );
    } catch (e) {
      throw ServerFailure('حدث خطأ غير متوقع أثناء تسجيل الدخول: $e');
    }
  }

  @override
  Future<void> signInAnonymously() async {
    try {
      // Check if already signed in
      if (firebaseAuth.currentUser != null) {
        return;
      }
      await firebaseAuth.signInAnonymously();
    } catch (_) {
      // If anonymous sign-in fails, continue anyway
      // (might already be signed in or in test environment)
    }
  }

  @override
  Future<bool> verifyAdminPassword(String email, String password) async {
    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    // ── Step 1: Try Firebase Auth sign-in ──
    try {
      final credential = await firebaseAuth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: cleanPassword,
      );
      // Keep signed in for Firestore access
      return credential.user != null;
    } catch (e) {
      // Firebase Auth failed, will try Firestore fallback
    }

    // ── Step 2: Fallback - check Firestore for temporary password ──
    try {
      // Ensure anonymous auth for Firestore access
      if (firebaseAuth.currentUser == null) {
        await signInAnonymously();
      }

      final query = await firestore
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return false;
      }

      final userDoc = query.docs.first;
      final userData = userDoc.data();
      final storedPassword =
          (userData['password'] as String?) ??
          (userData['temporaryPassword'] as String?) ??
          (userData['tempPassword'] as String?);

      if (storedPassword != null && storedPassword.trim() == cleanPassword) {
        // Self-heal: create Firebase Auth account for next time
        try {
          await firebaseAuth.createUserWithEmailAndPassword(
            email: cleanEmail,
            password: cleanPassword,
          );
          // Stay signed in with the new account
        } catch (_) {
          // Account might already exist with a different password
          // User is still authenticated anonymously
        }
        return true;
      }

      // ── Step 3: User exists but no stored password ──
      // This handles legacy accounts created before password field was added.
      // Verify user belongs to the system then accept the password and save it.
      final userRole = userData['role'] as String? ?? '';
      if (storedPassword == null &&
          (userRole == 'company-admin' ||
              userRole == 'organization-admin' ||
              userRole == 'Supervisor' ||
              userRole == 'marketing')) {
        // Save the password to Firestore for future logins
        try {
          await firestore.collection('users').doc(userDoc.id).update({
            'password': cleanPassword,
          });
        } catch (_) {}

        // Create Firebase Auth account
        try {
          await firebaseAuth.createUserWithEmailAndPassword(
            email: cleanEmail,
            password: cleanPassword,
          );
        } catch (_) {}

        return true;
      }

      return false;
    } catch (fallbackError) {
      return false;
    }
  }
}
