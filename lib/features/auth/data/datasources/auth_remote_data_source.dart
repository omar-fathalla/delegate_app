import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/auth/data/datasources/totp_mfa.dart';
import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:delegate_app/core/security/delegate_identity.dart';

abstract class AuthRemoteDataSource {
  /// Staff lookup by phone. Uses `staffPhoneLookup` when it is deployed.
  /// Falls back to the `users` collection only when that callable is missing.
  /// Does not query `delegates` and does not create an auth session.
  ///
  /// Delegate credential login uses [loginDelegate] and does not call this.
  Future<List<DelegateModel>> getDelegatesByPhone(String phoneNumber);

  /// TAS-272: a signed-in delegate's own copies in every chain (the same
  /// collectionGroup('delegates') phone query as login; the rules allow it
  /// for the phones in the delegate token). Used to refresh the
  /// «تبديل المنظمة» list, which [getDelegatesByPhone] (staff only) never did.
  Future<List<DelegateModel>> refreshDelegateProfiles(String phoneNumber);

  /// Verifies phone + national ID with `delegateLoginV2`, then signs in with
  /// the returned custom token. Does not compare the national ID on the device.
  Future<List<DelegateModel>> loginDelegate({
    required String phoneNumber,
    required String nationalId,
  });

  /// Verifies a non-delegate password with Firebase Auth email/password.
  ///
  /// Throws `MfaRequiredFailure` when the password is right and the account
  /// has TOTP two-step verification (TAS-207), and an [AuthFailure] with code
  /// `mfa_unsupported` when its only second factor is not TOTP.
  Future<bool> verifyAdminPassword(String email, String password);

  /// Looks up the staff email for [phoneNumber], then verifies it with
  /// Firebase Auth. Does not compare a password stored in Firestore.
  Future<bool> verifyPhonePassword(String phoneNumber, String password);

  /// Ends the Firebase Auth session. Failures are swallowed so logout can
  /// still clear local state when the device is offline.
  Future<void> signOut();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseAuth firebaseAuth;
  final DelegateLoginApi? delegateLoginApi;
  final StaffPhoneLookupApi? staffPhoneLookupApi;
  final Future<Map<String, String>> Function()? currentDeviceDetails;

  AuthRemoteDataSourceImpl({
    required this.firestore,
    required this.firebaseAuth,
    this.delegateLoginApi,
    this.staffPhoneLookupApi,
    this.currentDeviceDetails,
    this.totpSignInAssertion = defaultTotpSignInAssertion,
  });

  /// Test seam for the TOTP sign-in assertion (TAS-207).
  final TotpSignInAssertion totpSignInAssertion;

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

    if (!WebRuntimePolicy.delegateDeviceBindingEnabled) {
      throw const AuthFailure(
        WebRuntimePolicy.delegateLoginWebMessage,
        'delegate_web_app_only',
      );
    }

    final details = await (currentDeviceDetails ??
        DeviceBindingService.getCurrentDeviceDetails)();
    final deviceId = (details['deviceId'] ?? '').trim();
    final deviceModel = (details['deviceModel'] ?? '').trim();
    final legacyDeviceId = (details['legacyDeviceId'] ?? '').trim();

    late final DelegateLoginResponse response;
    try {
      response = await api.login(
        phone: phoneNumber,
        nationalId: nationalId,
        deviceId: deviceId,
        deviceModel: deviceModel,
        legacyDeviceId: legacyDeviceId,
      );
    } on DelegateLoginException catch (error) {
      throw _failureForDelegateLogin(error);
    }

    try {
      await firebaseAuth.signInWithCustomToken(response.token);
      // TAS-28 phase 0: cache the delegateId claim for DelegateIdentity.
      await DelegateIdentity.refresh(firebaseAuth);
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
          'هذا الحساب موقوف حاليًا. يرجى التواصل مع إدارة تسهيل.',
        );
      case 'id_under_review':
        // TAS-373: a supervisor replaced the ID card; review, not suspension.
        return const AuthFailure(
          'بطاقتك اتغيرت ومستنية مراجعة الإدارة. هتقدر تدخل أول ما تتراجع.',
        );
      case 'rate_limited':
        return const DelegateRateLimitFailure(
          'تم تجاوز عدد المحاولات. يرجى المحاولة لاحقاً.',
        );
      case 'device_mismatch':
        return AuthFailure(deviceMismatchMessage(error.details), 'device_mismatch');
      case 'invalid_device':
        return const AuthFailure(
          'تعذر قراءة معرّف هذا الجهاز. أعد فتح التطبيق وحاول مرة أخرى.',
          'invalid_device',
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

  @override
  Future<void> signOut() => _signOutQuietly();

  Future<void> _signOutQuietly() async {
    BranchesSessionCache.invalidate();
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
  Future<List<DelegateModel>> refreshDelegateProfiles(String phoneNumber) {
    return _loadDelegateModelsByPhone(_normalizePhone(phoneNumber));
  }

  @override
  Future<List<DelegateModel>> getDelegatesByPhone(String phoneNumber) async {
    try {
      final normalizedPhone = _normalizePhone(phoneNumber);
      final lookedUp = await _staffFromCallable(phoneNumber, normalizedPhone);
      if (lookedUp != null) return lookedUp;
      final docs = await _staffUserDocs(phoneNumber);
      final delegates = <DelegateModel>[];
      for (final userDoc in docs) {
        final model = _staffModelFromUserDoc(userDoc, normalizedPhone);
        if (model == null) continue;
        delegates.add(model);
        break;
      }
      return delegates;
    } on Failure {
      rethrow;
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
    } on FirebaseAuthMultiFactorException catch (e) {
      // TAS-207: the password is right, the account has two-step
      // verification. Hand the resolver up so the screen asks for the code.
      throw mfaFailureFromResolver(
        e.resolver,
        assertionFor: totpSignInAssertion,
      );
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
    } on AuthFailure {
      // Two-step verification required or unsupported (TAS-207).
      rethrow;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _staffEmailForPhone(String phoneNumber) async {
    try {
      final lookedUp = await _staffFromCallable(
        phoneNumber,
        _normalizePhone(phoneNumber),
      );
      if (lookedUp != null) {
        if (lookedUp.isEmpty) return null;
        final email = lookedUp.first.email?.trim() ?? '';
        return email.isEmpty ? null : email;
      }
      final docs = await _staffUserDocs(phoneNumber);
      for (final doc in docs) {
        final email = _stringField(doc.data(), const ['email']);
        if (_staffRoleWeight(doc.data()['role'] as String? ?? '') == 0) {
          continue;
        }
        if (email.isNotEmpty) return email;
      }
    } catch (_) {}
    return null;
  }

  /// Null means the callable is not deployed and the users query should run.
  /// An empty list means the callable answered and there is no staff account.
  Future<List<DelegateModel>?> _staffFromCallable(
    String phoneNumber,
    String normalizedPhone,
  ) async {
    final api = staffPhoneLookupApi;
    if (api == null) return null;
    try {
      final profile = await api.lookup(phoneNumber);
      if (profile == null) return const [];
      if (!profile.isComplete) {
        // TAS-314: signed out, the callable gives the email only. This
        // placeholder (empty uid) carries the email to the password check;
        // the Login use case swaps it for the full profile after sign-in.
        final pending = _staffModelFromData(
          '',
          {'role': 'admin', 'email': profile.email},
          normalizedPhone,
        );
        return pending == null ? const [] : [pending];
      }
      final model = _staffModelFromData(
        profile.uid,
        {
          'role': profile.role,
          'email': profile.email,
          'displayName': profile.displayName,
          'organizationUID': profile.organizationUID,
          'organizationName': profile.organizationName,
          'companyUID': profile.companyUID,
          'companyName': profile.companyName,
        },
        normalizedPhone,
      );
      if (model == null) return const [];
      return [model];
    } on StaffPhoneLookupException catch (error) {
      if (error.reason == 'unavailable') return null;
      if (error.reason == 'not_found') return const [];
      return const [];
    }
  }

  /// Users-collection lookup shared by staff login. Used only when
  /// `staffPhoneLookup` is not deployed yet. The tightened rules reject it.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _staffUserDocs(
    String phoneNumber,
  ) async {
    final normalizedPhone = _normalizePhone(phoneNumber);
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    final primary = await _safeLoginQuery(
      firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: normalizedPhone),
      'users collection',
    );
    docs.addAll(primary?.docs ?? const []);

    if (docs.isEmpty && phoneNumber.trim() != normalizedPhone) {
      try {
        final fallback = await firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: phoneNumber.trim())
            .getResilient(
              timeout: const Duration(seconds: 5),
              forceServer: true,
            );
        docs.addAll(fallback.docs);
      } catch (_) {}
    }
    if (docs.isEmpty) {
      try {
        final alias = await firestore
            .collection('users')
            .where('phone', isEqualTo: normalizedPhone)
            .getResilient(
              timeout: const Duration(seconds: 5),
              forceServer: true,
            );
        docs.addAll(alias.docs);
      } catch (_) {}
    }

    docs.sort((a, b) {
      final weightA = _staffRoleWeight(a.data()['role'] as String? ?? '');
      final weightB = _staffRoleWeight(b.data()['role'] as String? ?? '');
      return weightB.compareTo(weightA);
    });
    return docs;
  }

  DelegateModel? _staffModelFromUserDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    String normalizedPhone,
  ) {
    return _staffModelFromData(userDoc.id, userDoc.data(), normalizedPhone);
  }

  DelegateModel? _staffModelFromData(
    String uid,
    Map<String, dynamic> userData,
    String normalizedPhone,
  ) {
    final userRole = userData['role'] as String? ?? '';
    final normRole = userRole.toLowerCase().replaceAll('-', '_');
    final isSuperAdmin =
        normRole == 'super_admin' || normRole == 'superadmin';
    final isTechSupport = normRole == 'technical_support' ||
        normRole == 'technicalsupport' ||
        normRole == 'tech_support' ||
        normRole == 'techsupport';
    final isAccountant = normRole == 'accountant' ||
        normRole == 'accounting' ||
        normRole == 'account_admin';
    final isOrgAdmin =
        normRole == 'organization_admin' || normRole == 'organizationadmin';
    final isCompanyAdmin = normRole == 'company_admin' ||
        normRole == 'companyadmin' ||
        normRole == 'admin';
    final isSupervisor = isSupervisorRole(userRole);
    final isMarketing = normRole == 'marketing';
    final isMarketingPromotion = normRole == 'marketing_promotion' ||
        normRole == 'marketingpromotion';
    final isBranchesMarketing = normRole == 'branches_marketing' ||
        normRole == 'branches_marketing_manager' ||
        normRole == 'branchesmarketingmanager';
    final isHR = normRole == 'hr' ||
        normRole == 'company_hr' ||
        normRole == 'company-hr' ||
        normRole == 'human_resources';

    if (!(isSuperAdmin ||
        isTechSupport ||
        isAccountant ||
        isOrgAdmin ||
        isCompanyAdmin ||
        isSupervisor ||
        isMarketing ||
        isMarketingPromotion ||
        isBranchesMarketing ||
        isHR)) {
      return null;
    }

    final adminEmail = _stringField(userData, const ['email']);
    if (adminEmail.isEmpty) return null;

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

    return DelegateModel(
      uid: uid,
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
      createdAt: _readCreatedAt(userData) ?? DateTime.fromMillisecondsSinceEpoch(0),
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
    );
  }

  static DateTime? _readCreatedAt(Map<String, dynamic> data) {
    final value = data['createdAt'] ?? data['created_at'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
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

  /// True for `supervisor` and company supervisor spellings such as
  /// `company_supervisor`, `companySupervisor`, and `company-supervisor`.
  static bool isSupervisorRole(String role) {
    final norm =
        role.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return norm == 'supervisor' ||
        norm == 'company_supervisor' ||
        norm == 'companysupervisor';
  }

  @visibleForTesting
  static int staffRoleWeightForTest(String role) => _staffRoleWeight(role);

  /// Email for a staff phone, for the "forgot password" flow. Null when the
  /// lookup is unavailable or the phone is not a staff account. Read-only.
  Future<String?> lookupStaffEmail(String phoneNumber) =>
      _staffEmailForPhone(phoneNumber);

  static int _staffRoleWeight(String role) {
    final norm = role.trim().toLowerCase().replaceAll('-', '_');
    if (norm == 'super_admin' || norm == 'superadmin') return 100;
    if (norm == 'technical_support' ||
        norm == 'technicalsupport' ||
        norm == 'tech_support' ||
        norm == 'techsupport') {
      return 90;
    }
    if (norm == 'accountant' || norm == 'accounting' || norm == 'account_admin') {
      return 85;
    }
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
    if (isSupervisorRole(norm)) return 60;
    if (norm == 'marketing' ||
        norm == 'marketing_promotion' ||
        norm == 'marketingpromotion') {
      return 50;
    }
    return 0;
  }
}

/// TAS-367: the device-mismatch message, with the supervisor to call and
/// how long the request has waited when the server sent them.
String deviceMismatchMessage(Map<String, dynamic> details, {DateTime? now}) {
  final buf = StringBuffer(
    'هذا الحساب مقترن بجهاز آخر. تم إرسال طلب تغيير الجهاز إلى إدارة الشركة. بعد الموافقة، سجّل الدخول من هذا الجهاز ليتم اعتماده.',
  );
  final name = (details['supervisorName'] ?? '').toString().trim();
  final phone = (details['supervisorPhone'] ?? '').toString().trim();
  if (name.isNotEmpty || phone.isNotEmpty) {
    buf.write(' كلّم المشرف${name.isNotEmpty ? ' $name' : ''}');
    if (phone.isNotEmpty) buf.write(' على \u2066$phone\u2069');
    buf.write(' علشان يوافق.');
  }
  final at = details['requestCreatedAtMs'];
  if (at is num) {
    final hours = (now ?? DateTime.now())
        .difference(DateTime.fromMillisecondsSinceEpoch(at.toInt()))
        .inHours;
    if (hours >= 1) buf.write(' الطلب مستني بقاله $hours ساعة.');
  }
  return buf.toString();
}
