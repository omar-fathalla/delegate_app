// Web: every company supervisor / HR user-document shape lands on the HR
// desktop system (/hr/home) after login and after a reload, and mobile-style
// homes redirect there. Mobile routing is unchanged. Fake data only.
import 'dart:async';

import 'package:delegate_app/config/routes/app_router.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/auth/domain/role_home.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/web_hr_system_redirect_web.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthBloc extends Mock implements AuthBloc {}

class _MockPush extends Mock implements PushNotificationService {}

class _Lookup implements StaffPhoneLookupApi {
  _Lookup(this.profile);
  final StaffPhoneProfile profile;
  @override
  Future<StaffPhoneProfile?> lookup(String phone) async => profile;
}

const _org = 'seed-fake-hr-org';
const _co = 'seed-fake-co-alpha';

/// `users/{uid}` shapes a company supervisor or HR can have in production,
/// written by the Angular invite (`claimInvite`), `createStaffUser`, the app's
/// create-admin screen, client grants and legacy imports.
final Map<String, Map<String, dynamic>> _shapes = {
  'supervisor + companyUID (createStaffUser, current fake seed)': {
    'role': 'supervisor',
    'companyUID': _co,
  },
  'company_supervisor + companyUID + jobTitle': {
    'role': 'company_supervisor',
    'companyUID': _co,
    'jobTitle': 'مشرف',
  },
  'company-admin from the Angular invite (claimInvite)': {
    'role': 'company-admin',
    'companyUID': _co,
    'companyName': 'Fake Company Alpha',
    'emailVerified': true,
    'status': 'Approved',
  },
  'company_admin + companyUID': {'role': 'company_admin', 'companyUID': _co},
  'companyadmin with legacy companyId only': {
    'role': 'companyadmin',
    'companyId': _co,
  },
  'admin + position supervisor': {
    'role': 'admin',
    'companyUID': _co,
    'position': 'supervisor',
  },
  'Admin (capitalised) + userType HR': {
    'role': 'Admin',
    'userType': 'HR',
    'companyUID': _co,
  },
  'legacy admin without any company field': {'role': 'admin'},
  'hr from the app create-admin screen': {
    'role': 'hr',
    'companyUID': _co,
    'jobTitle': 'HR',
    'isActive': true,
  },
  'HR (capitalised) + userType HR': {
    'role': 'HR',
    'userType': 'HR',
    'companyUID': _co,
  },
  'company-hr (legacy)': {'role': 'company-hr', 'companyUID': _co},
  'company_hr': {'role': 'company_hr', 'companyUID': _co},
  'human_resources': {'role': 'human_resources', 'companyId': _co},
};

const _notHrSystem = {
  'super-admin': UserRole.superAdmin,
  'technical_support': UserRole.technicalSupport,
  'organization-admin': UserRole.organizationAdmin,
  'branches_marketing': UserRole.branchesMarketingManager,
  'marketing': UserRole.marketing,
  'marketing_promotion': UserRole.marketingPromotion,
  'accountant': UserRole.accountant,
};

Future<DelegateModel> _staffLogin(Map<String, dynamic> shape) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('seed-fake-shape').set({
    'email': 'fake.shape@example.com',
    'displayName': 'Fake Shape',
    'phoneNumber': '01000000099',
    'organizationUID': _org,
    ...shape,
  });
  final source = AuthRemoteDataSourceImpl(
    firestore: firestore,
    firebaseAuth: MockFirebaseAuth(),
  );
  final result = await source.getDelegatesByPhone('01000000099');
  expect(result, hasLength(1), reason: '$shape');
  return result.single;
}

Delegate _delegate(UserRole role, {String companyUID = _co}) => Delegate(
  uid: 'seed-fake-${role.name}',
  firstName: 'مشرف',
  middleName: '',
  lastName: 'وهمي',
  fullName: 'مشرف وهمي',
  nationalityID: '__firebase_auth__:fake@example.com',
  motherName: '',
  city: '',
  phoneNumber: '01000000099',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: _org,
  organizationName: 'Fake Test Organization',
  companyUID: companyUID,
  companyName: companyUID.isEmpty ? '' : 'Fake Company Alpha',
  status: DelegateStatus.approved,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'system_admin',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: role,
  email: 'fake@example.com',
);

Widget _hrSystemStub(Delegate d) => Scaffold(
  key: const ValueKey('hr_system'),
  body: Text('HR system for ${d.role.name}'),
);

void main() {
  late _MockAuthBloc bloc;
  late StreamController<AuthState> authStates;

  setUpAll(() {
    registerFallbackValue(AuthInitial());
    registerFallbackValue(CheckAutoLoginRequested());
  });

  setUp(() async {
    sl.allowReassignment = true;
    authStates = StreamController<AuthState>.broadcast();
    bloc = _MockAuthBloc();
    when(() => bloc.state).thenReturn(AuthInitial());
    when(() => bloc.stream).thenAnswer((_) => authStates.stream);
    when(() => bloc.close()).thenAnswer((_) async {});
    if (!sl.isRegistered<SharedPreferences>()) {
      SharedPreferences.setMockInitialValues({'app_locale': 'ar'});
      final prefs = await SharedPreferences.getInstance();
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
      localeProvider = sl<LocaleProvider>();
    }
    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(sl<SharedPreferences>()));
    }
    final push = _MockPush();
    when(() => push.initialize(any())).thenAnswer((_) async {});
    sl.registerSingleton<PushNotificationService>(push);
    WebHrSystemRedirect.debugHrSystemBuilder = _hrSystemStub;
  });

  tearDown(() async {
    WebRuntimePolicy.debugReset();
    WebHrSystemRedirect.debugHrSystemBuilder = null;
    await authStates.close();
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  group('landing path', () {
    test('web sends company supervisors and HR to the HR system only', () {
      for (final role in UserRole.values) {
        final expected = role == UserRole.admin || role == UserRole.hr
            ? '/hr/home'
            : homePathForRole(role);
        expect(
          landingPathForRole(role, isWeb: true),
          expected,
          reason: role.name,
        );
      }
    });

    test('mobile keeps every role home unchanged', () {
      for (final role in UserRole.values) {
        expect(
          landingPathForRole(role, isWeb: false),
          homePathForRole(role),
          reason: role.name,
        );
      }
      WebRuntimePolicy.debugIsWebOverride = false;
      expect(landingPathForRole(UserRole.admin), '/admin/home');
      expect(landingPathForRole(UserRole.hr), '/hr/home');
      expect(WebHrSystemRedirect.appliesTo(_delegate(UserRole.admin)), isFalse);
    });

    test('delegates are never routed into the HR system', () {
      expect(landingPathForRole(UserRole.delegate, isWeb: true), '/home');
      expect(usesWebHrSystem(UserRole.delegate, isWeb: true), isFalse);
    });
  });

  group('every prod supervisor / HR shape', () {
    for (final entry in _shapes.entries) {
      test('${entry.key}: web login and reload land on /hr/home', () async {
        final model = await _staffLogin(entry.value);
        expect(model.role, anyOf(UserRole.admin, UserRole.hr));
        expect(landingPathForRole(model.role, isWeb: true), '/hr/home');
        expect(
          landingPathForRole(model.role, isWeb: false),
          homePathForRole(model.role),
        );
        final hasCompany =
            entry.value.containsKey('companyUID') ||
            entry.value.containsKey('companyId');
        expect(model.companyUID, hasCompany ? _co : '');

        // Reload: the splash restores the cached session.
        SharedPreferences.setMockInitialValues({});
        final local = AuthLocalDataSourceImpl(
          sharedPreferences: await SharedPreferences.getInstance(),
        );
        await local.cacheDelegateData(model);
        final restored = local.getCachedDelegateData()!;
        expect(restored.role, model.role);
        expect(restored.companyUID, model.companyUID);
        expect(landingPathForRole(restored.role, isWeb: true), '/hr/home');
      });
    }

    test(
      'callable path: company-admin invite profile lands on /hr/home',
      () async {
        final source = AuthRemoteDataSourceImpl(
          firestore: FakeFirebaseFirestore(),
          firebaseAuth: MockFirebaseAuth(),
          staffPhoneLookupApi: _Lookup(
            const StaffPhoneProfile(
              uid: 'seed-fake-company-admin-invite-alpha',
              email: 'fake.companyadmin.invite.alpha@example.com',
              role: 'company-admin',
              displayName: 'Fake Company Admin Invite',
              phoneNumber: '01000000023',
              organizationUID: _org,
              companyUID: _co,
            ),
          ),
        );
        final model = (await source.getDelegatesByPhone('01000000023')).single;
        expect(model.role, UserRole.admin);
        expect(model.companyUID, _co);
        expect(landingPathForRole(model.role, isWeb: true), '/hr/home');
      },
    );

    for (final entry in _notHrSystem.entries) {
      test('${entry.key} keeps its own home on web', () async {
        final model = await _staffLogin({'role': entry.key});
        expect(model.role, entry.value);
        expect(
          landingPathForRole(model.role, isWeb: true),
          homePathForRole(entry.value),
        );
      });
    }
  });

  group('routing (production routes)', () {
    Future<GoRouter> pumpRouter(
      WidgetTester t, {
      required String initial,
      Object? extra,
      List<RouteBase>? routes,
      Size size = const Size(1280, 800),
    }) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      final router = GoRouter(
        initialLocation: initial,
        initialExtra: extra,
        routes: routes ?? appRouter.configuration.routes,
      );
      addTearDown(router.dispose);
      await t.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: bloc,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ar'),
          ),
        ),
      );
      await t.pumpAndSettle();
      return router;
    }

    String location(GoRouter r) =>
        r.routerDelegate.currentConfiguration.uri.toString();

    for (final role in [UserRole.admin, UserRole.hr]) {
      for (final path in ['/admin/home', '/home']) {
        testWidgets('web ${role.name} at $path is sent to the HR system', (
          t,
        ) async {
          WebRuntimePolicy.debugIsWebOverride = true;
          final r = await pumpRouter(t, initial: path, extra: _delegate(role));
          expect(location(r), '/hr/home');
          expect(find.byKey(const ValueKey('hr_system')), findsOneWidget);
          expect(find.text('HR system for ${role.name}'), findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);
        });
      }
    }

    testWidgets('web supervisor without a company still gets the HR system', (
      t,
    ) async {
      WebRuntimePolicy.debugIsWebOverride = true;
      final r = await pumpRouter(
        t,
        initial: '/admin/home',
        extra: _delegate(UserRole.admin, companyUID: ''),
      );
      expect(location(r), '/hr/home');
      expect(find.byKey(const ValueKey('hr_system')), findsOneWidget);
    });

    testWidgets('narrow web window (600dp) also gets the HR system', (t) async {
      WebRuntimePolicy.debugIsWebOverride = true;
      final r = await pumpRouter(
        t,
        initial: '/admin/home',
        extra: _delegate(UserRole.admin),
        size: const Size(600, 900),
      );
      expect(location(r), '/hr/home');
      expect(find.byKey(const ValueKey('hr_system')), findsOneWidget);
    });

    testWidgets('a stale ?p= from the old shell is dropped on redirect', (
      t,
    ) async {
      WebRuntimePolicy.debugIsWebOverride = true;
      final r = await pumpRouter(
        t,
        initial: '/admin/home?p=attendance',
        extra: _delegate(UserRole.admin),
      );
      expect(location(r), '/hr/home');
    });

    List<RouteBase> loginWithStubHomes() => [
      ...appRouter.configuration.routes.where(
        (route) => route is GoRoute && route.path == '/login',
      ),
      ...appRouter.configuration.routes.where(
        (route) => route is GoRoute && route.path == '/',
      ),
      for (final p in ['/admin/home', '/home', '/hr/home'])
        GoRoute(
          path: p,
          builder: (_, _) => Scaffold(body: Text('landed $p')),
        ),
    ];

    for (final web in [true, false]) {
      for (final role in [UserRole.admin, UserRole.hr]) {
        final expected = web ? '/hr/home' : homePathForRole(role);
        testWidgets(
          '${web ? 'web' : 'mobile'} login as ${role.name} goes to $expected',
          (t) async {
            WebRuntimePolicy.debugIsWebOverride = web;
            final r = await pumpRouter(
              t,
              initial: '/login',
              routes: loginWithStubHomes(),
            );
            authStates.add(AuthAuthenticated(delegate: _delegate(role)));
            await t.pumpAndSettle();
            expect(location(r), expected);
            expect(find.text('landed $expected'), findsOneWidget);
            await t.pump(const Duration(seconds: 2));
          },
        );

        testWidgets(
          '${web ? 'web' : 'mobile'} reload (splash) as ${role.name} goes to $expected',
          (t) async {
            WebRuntimePolicy.debugIsWebOverride = web;
            final r = await pumpRouter(
              t,
              initial: '/',
              routes: loginWithStubHomes(),
            );
            authStates.add(AuthAuthenticated(delegate: _delegate(role)));
            await t.pumpAndSettle();
            expect(location(r), expected);
            await t.pump(const Duration(seconds: 2));
          },
        );
      }
    }
  });
}
