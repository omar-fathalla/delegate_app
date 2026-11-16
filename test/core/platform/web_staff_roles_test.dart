import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/auth/domain/role_home.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Messaging extends Mock implements FirebaseMessaging {}

class _LocalNotifications extends Mock
    implements FlutterLocalNotificationsPlugin {}

class _Auth extends Fake implements FirebaseAuth {}

class _LoginApi implements DelegateLoginApi {
  int calls = 0;

  @override
  Future<DelegateLoginResponse> login({
    required String phone,
    required String nationalId,
    required String deviceId,
    String deviceModel = '',
  }) async {
    calls++;
    return const DelegateLoginResponse(token: 't', delegateIds: ['d1']);
  }
}

Delegate _delegate({
  UserRole role = UserRole.delegate,
  String companyUID = '',
  String? boundDeviceId,
}) {
  return Delegate(
    uid: 'u1',
    firstName: 'أحمد',
    middleName: '',
    lastName: 'علي',
    fullName: 'أحمد علي',
    nationalityID: '29001011234567',
    motherName: '',
    city: '',
    phoneNumber: '01000000000',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1990, 1, 1),
    organizationUID: 'org-1',
    organizationName: 'سلسلة',
    companyUID: companyUID,
    companyName: companyUID.isEmpty ? '' : 'شركة',
    status: DelegateStatus.active,
    delegatePublicId: 'D-1',
    allReceiptCodes: const [],
    createdAt: DateTime(2024, 1, 1),
    createdBy: 'seed',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    paymentAmount: 0,
    version: 1,
    documents: const [],
    role: role,
    boundDeviceId: boundDeviceId,
  );
}

void main() {
  tearDown(WebRuntimePolicy.debugReset);

  group('web runtime policy', () {
    test('mobile keeps device binding, check-in, tracking, and push', () {
      WebRuntimePolicy.debugIsWebOverride = false;
      expect(WebRuntimePolicy.loginKeepsModeTabs, isTrue);
      expect(WebRuntimePolicy.delegateDeviceBindingEnabled, isTrue);
      expect(WebRuntimePolicy.checkInEnabled, isTrue);
      expect(WebRuntimePolicy.liveTrackingEnabled, isTrue);
      expect(WebRuntimePolicy.pushNotificationsEnabled, isTrue);
      expect(
        WebRuntimePolicy.skipEmptyCompanyDelegateDirectory(companyUID: ''),
        isFalse,
      );
    });

    test(
      'web skips binding, check-in, tracking, push, and empty company paths',
      () {
        WebRuntimePolicy.debugIsWebOverride = true;
        expect(WebRuntimePolicy.loginKeepsModeTabs, isTrue);
        expect(WebRuntimePolicy.delegateDeviceBindingEnabled, isFalse);
        expect(WebRuntimePolicy.checkInEnabled, isFalse);
        expect(WebRuntimePolicy.liveTrackingEnabled, isFalse);
        expect(WebRuntimePolicy.pushNotificationsEnabled, isFalse);
        expect(
          WebRuntimePolicy.skipEmptyCompanyDelegateDirectory(companyUID: ''),
          isTrue,
        );
        expect(
          WebRuntimePolicy.skipEmptyCompanyDelegateDirectory(companyUID: 'c1'),
          isFalse,
        );
        expect(WebRuntimePolicy.checkInWebMessage, contains('تطبيق الجوال'));
        expect(WebRuntimePolicy.trackingWebMessage, contains('تطبيق الجوال'));
        expect(
          WebRuntimePolicy.delegateLoginWebMessage,
          contains('تطبيق الجوال'),
        );
      },
    );
  });

  group('role homes do not depend on companyUID', () {
    test('every staff role has a home, including an empty company', () {
      const expected = {
        UserRole.superAdmin: '/admin/home',
        UserRole.technicalSupport: '/admin/home',
        UserRole.organizationAdmin: '/admin/home',
        UserRole.admin: '/admin/home',
        UserRole.hr: '/hr/home',
        UserRole.marketing: '/marketing/home',
        UserRole.marketingPromotion: '/marketing/home',
        UserRole.branchesMarketingManager: '/admin/home',
        UserRole.accountant: '/accountant/home',
        UserRole.delegate: '/home',
      };
      for (final role in UserRole.values) {
        final withCompany = _delegate(role: role, companyUID: 'c1');
        final withoutCompany = _delegate(role: role);
        expect(homePathForRole(withCompany.role), expected[role]);
        expect(homePathForRole(withoutCompany.role), expected[role]);
        expect(withoutCompany.companyUID, isEmpty);
      }
    });

    test('admin shell kind matches the role, not the company', () {
      expect(adminShellKindFor(UserRole.superAdmin), AdminShellKind.superAdmin);
      expect(
        adminShellKindFor(UserRole.technicalSupport),
        AdminShellKind.technicalSupport,
      );
      expect(
        adminShellKindFor(UserRole.organizationAdmin),
        AdminShellKind.organizationAdmin,
      );
      expect(
        adminShellKindFor(UserRole.branchesMarketingManager),
        AdminShellKind.branchesMarketingManager,
      );
      expect(
        adminShellKindFor(UserRole.admin),
        AdminShellKind.companySupervisor,
      );
      expect(adminShellKindFor(UserRole.hr), AdminShellKind.companySupervisor);
    });
  });

  test('web delegate login does not read or send a device id', () async {
    WebRuntimePolicy.debugIsWebOverride = true;
    final api = _LoginApi();
    var detailReads = 0;
    final source = AuthRemoteDataSourceImpl(
      firestore: FakeFirebaseFirestore(),
      firebaseAuth: _Auth(),
      delegateLoginApi: api,
      currentDeviceDetails: () async {
        detailReads++;
        return {'deviceId': 'phone-should-not-be-read'};
      },
    );

    await expectLater(
      source.loginDelegate(
        phoneNumber: '01000000000',
        nationalId: '29001011234567',
      ),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.code,
          'code',
          'delegate_web_app_only',
        ),
      ),
    );
    expect(api.calls, 0);
    expect(detailReads, 0);
  });

  test('web does not check or write a delegate device binding', () async {
    WebRuntimePolicy.debugIsWebOverride = true;
    final result = await DeviceBindingService.verifyOrBindDevice(
      delegate: _delegate(boundDeviceId: 'android-install-9'),
    );
    expect(result.status, DeviceVerificationStatus.bypassed);
    expect(result.isMismatched, isFalse);
    expect(result.isAllowed, isTrue);
  });

  test('web does not start live tracking or ask for location', () async {
    WebRuntimePolicy.debugIsWebOverride = true;
    final engine = DelegateTrackingEngine(
      trackingService: DelegateTrackingService(
        firestore: FakeFirebaseFirestore(),
      ),
    );
    await engine.startTrackingSession(delegateId: 'delegate-1');
    expect(engine.isTracking, isFalse);
    expect(engine.activeDelegateId, isNull);
  });

  test('web push init does not request a token', () async {
    WebRuntimePolicy.debugIsWebOverride = true;
    final messaging = _Messaging();
    final service = PushNotificationService(
      firestore: FakeFirebaseFirestore(),
      messaging: messaging,
      localNotifications: _LocalNotifications(),
    );
    await service.initialize('delegate-1');
    await service.clearToken('delegate-1');
    verifyNever(() => messaging.getToken());
    verifyNever(() => messaging.requestPermission());
    verifyNever(() => messaging.deleteToken());
  });
}
