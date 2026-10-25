import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

abstract class AuthRemoteDataSource {
  /// Queries the `delegates` collectionGroup by phone number.
  /// Returns a list of [DelegateModel] matching the phone number.
  /// May contain multiple documents if delegate is registered in multiple orgs.
  ///
  /// Staff and other non-delegate roles still use this path. Delegate
  /// credential login uses [loginDelegate] and does not call it.
  Future<List<DelegateModel>> getDelegatesByPhone(String phoneNumber);

  /// Verifies phone + national ID with `delegateLoginV2`, then signs in with
  /// the returned custom token. Does not sign in anonymously and does not
  /// compare the national ID on the device.
  Future<List<DelegateModel>> loginDelegate({
    required String phoneNumber,
    required String nationalId,
  });

  /// Anonymous sign-in for the staff lookup path only.
  /// Delegate credential login must not call this.
  Future<void> signInAnonymously();

  /// Verifies a non-delegate password with Firebase Auth email/password.
  Future<bool> verifyAdminPassword(String email, String password);

  /// Looks up the staff email for [phoneNumber], then verifies it with
  /// Firebase Auth. Does not compare a password stored in Firestore.
  Future<bool> verifyPhonePassword(String phoneNumber, String password);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseAuth firebaseAuth;
  final DelegateLoginApi? delegateLoginApi;

  AuthRemoteDataSourceImpl({
    required this.firestore,
    required this.firebaseAuth,
    this.delegateLoginApi,
  });

  /// Normalises a phone number by stripping common Egyptian prefixes
  /// (`+2`, `+20`, `002`, `0020`) so queries match the bare format
  /// stored in Firestore (e.g. `"01274114404"`).
  String _normalizePhone(String phone) => normalizeEgyptianPhone(phone);

  @override
  Future<List<DelegateModel>> loginDelegate({
    required String phoneNumber,
    required String nationalId,
  }) async {
    final api = delegateLoginApi;
    if (api == null) {
      throw const AuthFailure(
        'تعذر تسجيل الدخول حالياً. يرجى المحاولة مرة أخرى.',
        'unavailable',
      );
    }

    late final DelegateLoginResponse response;
    try {
      response = await api.login(phone: phoneNumber, nationalId: nationalId);
    } on DelegateLoginException catch (error) {
      throw _failureForDelegateLogin(error);
    }

    try {
      await firebaseAuth.signInWithCustomToken(response.token);
    } catch (error) {
      debugPrint('delegate custom token sign-in failed: $error');
      throw const AuthFailure(
        'تعذر تسجيل الدخول حالياً. يرجى المحاولة مرة أخرى.',
        'unavailable',
      );
    }

    try {
      final normalizedPhone = _normalizePhone(phoneNumber);
      final models = await _loadDelegateModelsByPhone(normalizedPhone);
      final allowed = response.delegateIds.toSet();
      final matched = models.where((model) => allowed.contains(model.uid)).toList();
      if (matched.isEmpty) {
        await _signOutQuietly();
        throw const AuthFailure(
          'تعذر تسجيل الدخول حالياً. يرجى المحاولة مرة أخرى.',
          'unavailable',
        );
      }
      return matched;
    } on Failure {
      await _signOutQuietly();
      rethrow;
    } catch (error) {
      await _signOutQuietly();
      debugPrint('delegate profile load failed: $error');
      throw const AuthFailure(
        'تعذر تسجيل الدخول حالياً. يرجى المحاولة مرة أخرى.',
        'unavailable',
      );
    }
  }

  Failure _failureForDelegateLogin(DelegateLoginException error) {
    switch (error.reason) {
      case 'not_found':
      case 'bad_credentials':
        return const DelegateCredentialsFailure(
          'رقم الهاتف أو الرقم القومي غير صحيح',
        );
      case 'account_inactive':
        return const DelegateAccountInactiveFailure(
          'هذا الحساب قيد المراجعة أو موقوف. يرجى التواصل مع مسؤول الشركة.',
        );
      case 'rate_limited':
        return const DelegateRateLimitFailure(
          'تم تجاوز عدد المحاولات. يرجى المحاولة لاحقاً.',
        );
      case 'invalid_phone':
        return const AuthFailure(
          'يرجى إدخال رقم موبايل صحيح',
          'invalid_phone',
        );
      case 'invalid_national_id':
        return const AuthFailure(
          'يرجى إدخال الرقم القومي',
          'invalid_national_id',
        );
      default:
        return const AuthFailure(
          'تعذر تسجيل الدخول حالياً. يرجى المحاولة مرة أخرى.',
          'unavailable',
        );
    }
  }

  Future<void> _signOutQuietly() async {
    try {
      await firebaseAuth.signOut();
    } catch (_) {}
  }

  Future<QuerySnapshot<Map<String, dynamic>>?> _safeLoginQuery(
    Query<Map<String, dynamic>> query,
    String debugLabel,
  ) async {
    try {
      return await query
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
    } catch (serverError) {
      debugPrint('$debugLabel server query error ($serverError). Trying serverAndCache fallback.');
      try {
        final fallbackSnap = await query
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 8));
        return fallbackSnap;
      } catch (e) {
        debugPrint('$debugLabel fallback error: $e');
        try {
          final cacheSnap = await query.get(const GetOptions(source: Source.cache));
          if (cacheSnap.docs.isNotEmpty) {
            return cacheSnap;
          }
        } catch (_) {}

        final errStr = serverError.toString().toLowerCase();
        if (errStr.contains('timeout')) {
          throw const ServerFailure(
            'انتهت مهلة الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت والمحاولة مرة أخرى.',
          );
        } else if (errStr.contains('socket') ||
            errStr.contains('network') ||
            errStr.contains('unavailable')) {
          throw const ServerFailure(
            'تعذر الاتصال بالإنترنت. يرجى التأكد من تشغيل البيانات أو الواي فاي والمحاولة ثانية.',
          );
        }
        throw const ServerFailure(
          'تعذر التحقق من الحساب حالياً بسبب ضعف الاتصال. يرجى المحاولة مرة أخرى.',
        );
      }
    }
  }

  Future<List<DelegateModel>> _loadDelegateModelsByPhone(String normalizedPhone) async {
    final variants = egyptianPhoneVariants(normalizedPhone);
    final byPath = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    Future<void> collect(String field) async {
      final snap = await _safeLoginQuery(
        firestore.collectionGroup('delegates').where(field, whereIn: variants),
        'delegate login $field',
      );
      for (final doc in snap?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
        byPath[doc.reference.path] = doc;
      }
    }

    await collect('phoneNumber');
    if (byPath.isEmpty) {
      try {
        await collect('phone');
      } catch (error) {
        debugPrint('delegate phone-field fallback skipped: $error');
      }
    }
    return _modelsFromDelegateDocs(byPath.values);
  }

  List<DelegateModel> _modelsFromDelegateDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final delegatesMap = <String, DelegateModel>{};
    for (final doc in docs) {
      final data = doc.data();
      var model = DelegateModel.fromJson(data, doc.id);

      // Path: organizations/{orgUID}/companies/{compUID}/delegates/{delegateUID}
      final pathSegments = doc.reference.path.split('/');
      final pathOrgUID = (pathSegments.length >= 2 && pathSegments[0] == 'organizations')
          ? pathSegments[1]
          : '';
      final pathCompUID = (pathSegments.length >= 4 && pathSegments[2] == 'companies')
          ? pathSegments[3]
          : '';

      if (pathOrgUID.isNotEmpty && model.organizationUID != pathOrgUID) {
        model = model.copyWith(organizationUID: pathOrgUID);
      }
      if (pathCompUID.isNotEmpty && model.companyUID != pathCompUID) {
        model = model.copyWith(companyUID: pathCompUID);
      }

      final key = '${model.uid}_${model.organizationUID}_${model.companyUID}';
      if (delegatesMap.containsKey(key)) {
        final existing = delegatesMap[key]!;
        if (existing.status != DelegateStatus.approved &&
            existing.status != DelegateStatus.active &&
            (model.status == DelegateStatus.approved || model.status == DelegateStatus.active)) {
          delegatesMap[key] = model;
        }
      } else {
        delegatesMap[key] = model;
      }
    }

    final allOrgNames = delegatesMap.values
        .map((d) => d.organizationName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    DateTime? earliestCreatedAt;
    for (final d in delegatesMap.values) {
      if (earliestCreatedAt == null || d.createdAt.isBefore(earliestCreatedAt)) {
        earliestCreatedAt = d.createdAt;
      }
    }

    for (final key in delegatesMap.keys.toList()) {
      var current = delegatesMap[key]!;
      if (allOrgNames.length > 1) {
        final mergedNames = {...current.allOrganizationNames, ...allOrgNames}.toList();
        current = current.copyWith(allOrganizationNames: mergedNames);
      }
      if (earliestCreatedAt != null && current.createdAt != earliestCreatedAt) {
        current = current.copyWith(createdAt: earliestCreatedAt);
      }
      delegatesMap[key] = current;
    }

    return delegatesMap.values.toList();
  }

  @override
  Future<List<DelegateModel>> getDelegatesByPhone(String phoneNumber) async {
    try {
      final normalizedPhone = _normalizePhone(phoneNumber);

      // Staff lookup still needs an auth session when nobody is signed in.
      // Delegate credential login does not come through this method.
      await signInAnonymously();

      final delegatesFuture = _safeLoginQuery(
        firestore
            .collectionGroup('delegates')
            .where('phoneNumber', isEqualTo: normalizedPhone),
        'delegates collectionGroup',
      );

      final usersFuture = _safeLoginQuery(
        firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: normalizedPhone),
        'users collection',
      );

      final results = await Future.wait([delegatesFuture, usersFuture]);
      final querySnapshot = results[0];
      var userQuery = results[1];

      final delegates = _modelsFromDelegateDocs(
        querySnapshot?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );

      // Also check if the user is an admin in the 'users' collection
      // (a phone number can exist in both delegates and users collections)
      try {
        var docs = userQuery?.docs.toList() ?? [];
        if (docs.isEmpty) {
          try {
            final fallbackQuery = await firestore
                .collection('users')
                .where('phoneNumber', isEqualTo: phoneNumber.trim())
                .getResilient(
                  timeout: const Duration(seconds: 5),
                  forceServer: true,
                );
            docs = fallbackQuery.docs.toList();
          } catch (_) {}
        }
        if (docs.isEmpty) {
          try {
            final phoneAlias = await firestore
                .collection('users')
                .where('phone', isEqualTo: normalizedPhone)
                .getResilient(
                  timeout: const Duration(seconds: 5),
                  forceServer: true,
                );
            docs = phoneAlias.docs.toList();
          } catch (_) {}
        }
        
        // Prioritize higher roles in case a phone number has multiple accounts
        docs.sort((a, b) {
          final roleA = a.data()['role'] as String? ?? '';
          final roleB = b.data()['role'] as String? ?? '';
          
          int getRoleWeight(String role) {
            final norm = role.toLowerCase().replaceAll('-', '_');
            if (norm == 'super_admin' || norm == 'superadmin') return 100;
            if (norm == 'technical_support' || norm == 'technicalsupport' || norm == 'tech_support' || norm == 'techsupport') return 90;
            if (norm == 'accountant' || norm == 'accounting') return 85;
            if (norm == 'organization_admin' || norm == 'organizationadmin') return 80;
            if (norm == 'hr' || norm == 'company_hr' || norm == 'company-hr' || norm == 'human_resources') return 75;
            if (norm == 'company_admin' || norm == 'companyadmin' || norm == 'admin') return 70;
            if (norm == 'branches_marketing' || norm == 'branches_marketing_manager' || norm == 'branchesmarketingmanager') return 65;
            if (norm == 'supervisor') return 60;
            if (norm == 'marketing' || norm == 'marketing_promotion' || norm == 'marketingpromotion') return 50;
            return 0;
          }
          
          return getRoleWeight(roleB).compareTo(getRoleWeight(roleA));
        });

        for (final userDoc in docs) {
          final userData = userDoc.data();
          final userRole = userData['role'] as String? ?? '';
          final normRole = userRole.toLowerCase().replaceAll('-', '_');
          final isSuperAdmin = normRole == 'super_admin' || normRole == 'superadmin';
          final isTechSupport = normRole == 'technical_support' ||
              normRole == 'technicalsupport' ||
              normRole == 'tech_support' ||
              normRole == 'techsupport';
          final isAccountant = normRole == 'accountant' || normRole == 'accounting' || normRole == 'account_admin';
          final isOrgAdmin = normRole == 'organization_admin' || normRole == 'organizationadmin';
          final isCompanyAdmin = normRole == 'company_admin' || normRole == 'companyadmin' || normRole == 'admin';
          final isSupervisor = normRole == 'supervisor';
          final isMarketing = normRole == 'marketing';
          final isMarketingPromotion = normRole == 'marketing_promotion' || normRole == 'marketingpromotion';
          final isBranchesMarketing = normRole == 'branches_marketing' ||
              normRole == 'branches_marketing_manager' ||
              normRole == 'branchesmarketingmanager';
          final isHR = normRole == 'hr' ||
              normRole == 'company_hr' ||
              normRole == 'company-hr' ||
              normRole == 'human_resources';

          if (isSuperAdmin ||
              isTechSupport ||
              isAccountant ||
              isOrgAdmin ||
              isCompanyAdmin ||
              isSupervisor ||
              isMarketing ||
              isMarketingPromotion ||
              isBranchesMarketing ||
              isHR) {
            // Firebase Auth email comes only from this document.
            final adminEmail = _stringField(userData, const ['email']);
            if (adminEmail.isEmpty) continue;

            final mappedRole = isHR
                ? UserRole.hr
                : isAccountant
                    ? UserRole.accountant
                    : isMarketing
                        ? UserRole.marketing
                        : isMarketingPromotion
                            ? UserRole.marketingPromotion
                            : isOrgAdmin
                                ? UserRole.organizationAdmin
                                : isTechSupport
                                    ? UserRole.technicalSupport
                                    : isSuperAdmin
                                        ? UserRole.superAdmin
                                        : isBranchesMarketing
                                            ? UserRole.branchesMarketingManager
                                            : UserRole.admin;

            final displayName = _stringField(
              userData,
              const ['displayName', 'fullName', 'name'],
            );
            final resolvedName = displayName.isEmpty ? 'Admin' : displayName;

            delegates.add(
              DelegateModel(
                uid: userDoc.id,
                firstName: resolvedName,
                middleName: '',
                lastName: '',
                fullName: resolvedName,
                nationalityID: '__firebase_auth__:$adminEmail',
                motherName: '',
                city: '',
                phoneNumber: normalizedPhone,
                gender: DelegateGender.male,
                position: DelegatePosition.supervisor,
                birthDate: DateTime.now(),
                organizationUID: _stringField(
                  userData,
                  const ['organizationUID', 'organizationId', 'orgId'],
                ),
                organizationName: _stringField(
                  userData,
                  const ['organizationName', 'organization_name'],
                ),
                companyUID: _stringField(
                  userData,
                  const ['companyUID', 'companyId'],
                ),
                companyName: _stringField(
                  userData,
                  const ['companyName', 'company_name'],
                ),
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
                role: mappedRole,
                email: adminEmail,
              ),
            );
            
            // Break after finding the first valid admin role to prevent duplicate delegates
            break;
          }
        }
      } on FirebaseException catch (_) {
        // Query failed — continue with delegates only.
      }

      return delegates;
    } on FirebaseException catch (e) {
      throw ServerFailure(
        'فشل في الاتصال بقاعدة البيانات. يرجى التحقق من الاتصال والمحاولة مرة أخرى. (${e.code})',
      );
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('timeout')) {
        throw const ServerFailure('انتهت مهلة الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت والمحاولة مرة أخرى.');
      } else if (errStr.contains('socket') || errStr.contains('network') || errStr.contains('unavailable')) {
        throw const ServerFailure('تعذر الاتصال بالإنترنت. يرجى التأكد من تشغيل البيانات أو الواي فاي والمحاولة ثانية.');
      }
      throw const ServerFailure('تعذر تسجيل الدخول حالياً. يرجى التأكد من صحة رقم الهاتف والمحاولة ثانية.');
    }
  }

  @override
  Future<void> signInAnonymously() async {
    try {
      // Check if already signed in
      if (firebaseAuth.currentUser != null) {
        return;
      }
      await firebaseAuth
          .signInAnonymously()
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      try {
        if (firebaseAuth.currentUser == null) {
          await firebaseAuth
              .signInAnonymously()
              .timeout(const Duration(seconds: 8));
        }
      } catch (_) {}
    }
  }

  @override
  Future<bool> verifyAdminPassword(String email, String password) async {
    final cleanEmail = email.trim();
    final cleanPass = password.trim();
    if (cleanEmail.isEmpty || cleanPass.isEmpty) return false;

    try {
      final credential = await firebaseAuth
          .signInWithEmailAndPassword(
            email: cleanEmail,
            password: cleanPass,
          )
          .timeout(const Duration(seconds: 12));
      return credential.user != null;
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuth admin signIn exception: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('FirebaseAuth admin signIn error: $e');
      return false;
    }
  }

  @override
  Future<bool> verifyPhonePassword(String phoneNumber, String password) async {
    try {
      final email = await _staffEmailForPhone(phoneNumber);
      if (email == null) return false;
      return await verifyAdminPassword(email, password);
    } catch (_) {
      return false;
    }
  }

  Future<String?> _staffEmailForPhone(String phoneNumber) async {
    final normalizedPhone = _normalizePhone(phoneNumber);
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    Future<void> addQuery(String field, String value) async {
      if (value.isEmpty) return;
      try {
        final snap = await firestore
            .collection('users')
            .where(field, isEqualTo: value)
            .getResilient(
              timeout: const Duration(seconds: 5),
              forceServer: true,
            );
        docs.addAll(snap.docs);
      } catch (_) {}
    }

    await addQuery('phoneNumber', normalizedPhone);
    if (phoneNumber.trim() != normalizedPhone) {
      await addQuery('phoneNumber', phoneNumber.trim());
    }
    if (docs.isEmpty) {
      await addQuery('phone', normalizedPhone);
    }

    docs.sort((a, b) {
      final weightA = _staffRoleWeight(a.data()['role'] as String? ?? '');
      final weightB = _staffRoleWeight(b.data()['role'] as String? ?? '');
      return weightB.compareTo(weightA);
    });

    for (final doc in docs) {
      final data = doc.data();
      if (_staffRoleWeight(data['role'] as String? ?? '') == 0) continue;
      final email = _stringField(data, const ['email']);
      if (email.isNotEmpty) return email;
    }
    return null;
  }

  static String _stringField(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static int _staffRoleWeight(String role) {
    final norm = role.toLowerCase().replaceAll('-', '_');
    if (norm == 'super_admin' || norm == 'superadmin') return 100;
    if (norm == 'technical_support' ||
        norm == 'technicalsupport' ||
        norm == 'tech_support' ||
        norm == 'techsupport') {
      return 90;
    }
    if (norm == 'accountant' || norm == 'accounting') return 85;
    if (norm == 'organization_admin' || norm == 'organizationadmin') return 80;
    if (norm == 'hr' ||
        norm == 'company_hr' ||
        norm == 'human_resources') {
      return 75;
    }
    if (norm == 'company_admin' || norm == 'companyadmin' || norm == 'admin') {
      return 70;
    }
    if (norm == 'branches_marketing' ||
        norm == 'branches_marketing_manager' ||
        norm == 'branchesmarketingmanager') {
      return 65;
    }
    if (norm == 'supervisor') return 60;
    if (norm == 'marketing' ||
        norm == 'marketing_promotion' ||
        norm == 'marketingpromotion') {
      return 50;
    }
    return 0;
  }
}
