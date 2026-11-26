// ignore_for_file: avoid_print
// Local/real-test entrypoint. Not used by release builds.
//
// Example:
// flutter run -t lib/main_real_test.dart -d emulator-5554 \
//   --dart-define=REAL_TEST_CUSTOM_TOKEN=... \
//   --dart-define=REAL_TEST_START_BRANCH_TAB=true
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/time/cairo_clock.dart';
import 'package:delegate_app/core/services/app_bloc_observer.dart';
import 'package:delegate_app/core/services/app_check_bootstrap.dart';
import 'package:delegate_app/core/services/crashlytics_service.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/core/services/app_version_gate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/main.dart' show MyApp, localeProvider;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/marketing/data/services/real_test_metrics.dart';
import 'package:delegate_app/features/marketing/data/services/delegate_profile_cache.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';

// TAS-78: no account data in lib/. Everything about the probe account comes
// from dart-defines, and ENV must be passed explicitly (the app default is
// prod, so a bare `flutter run -t lib/main_real_test.dart` used to sign in
// to production). Example (tashil-dev):
//   flutter run -t lib/main_real_test.dart --flavor dev --dart-define=ENV=dev \
//     --dart-define=REAL_TEST_CUSTOM_TOKEN=... --dart-define=REAL_TEST_UID=... \
//     --dart-define=REAL_TEST_EMAIL=... --dart-define=REAL_TEST_ORG=... \
//     --dart-define=REAL_TEST_PHONE=...
const _envGiven = bool.hasEnvironment('ENV');
const _token = String.fromEnvironment('REAL_TEST_CUSTOM_TOKEN');
const _uid = String.fromEnvironment('REAL_TEST_UID');
const _email = String.fromEnvironment('REAL_TEST_EMAIL');
const _org = String.fromEnvironment('REAL_TEST_ORG');
const _phone = String.fromEnvironment('REAL_TEST_PHONE');
const _favorites = <String>[
  'Smoha',
  'al-rehab',
  'Gardenia',
  'al-nasr',
  'Agmy Star',
  'Flemeing',
  'Abo Yousif',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CairoClock.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  if (!_envGiven) {
    throw StateError(
      'Pass --dart-define=ENV=dev (or ENV=prod on purpose); the real-test '
      'entrypoint no longer defaults to production (TAS-78).',
    );
  }
  for (final entry in const {
    'REAL_TEST_CUSTOM_TOKEN': _token,
    'REAL_TEST_UID': _uid,
    'REAL_TEST_EMAIL': _email,
    'REAL_TEST_ORG': _org,
  }.entries) {
    if (entry.value.isEmpty) {
      throw StateError('${entry.key} dart-define is required');
    }
  }

  final results = await Future.wait([
    Firebase.initializeApp(options: AppEnv.firebaseOptions),
    SharedPreferences.getInstance(),
  ]);
  // TAS-16: same App Check activation as the app (monitoring only).
  activateAppCheckMonitoring();
  final prefs = results[1] as SharedPreferences;

  final bootStart = DateTime.now().millisecondsSinceEpoch;
  print('[REAL_TEST] bootStart msSinceEpoch=$bootStart');

  if (RealTestMetrics.clearCold) {
    await prefs.remove('delegate_profile_cache_v1');
    DelegateProfileCache.clearSession();
    MarketingBloc.clearCache();
    MarketingBloc.resetColdFlagForTest();
    print('[REAL_TEST] cold caches cleared (prefs profile + session + branch cache)');
  }

  print('[REAL_TEST] signing in with custom token…');
  final cred = await FirebaseAuth.instance.signInWithCustomToken(_token);
  print('[REAL_TEST] auth.uid=${cred.user?.uid}');
  RealTestMetrics.markLoginDone();
  print('[REAL_TEST] startup_login_ms=${DateTime.now().millisecondsSinceEpoch - bootStart}');

  // Seed on-device favorites for this uid (app storage, not Firestore).
  await prefs.setString(
    'marketing_fav_branches_$_uid',
    json.encode(_favorites),
  );
  await prefs.setString('marketing_active_branch_$_uid', _favorites.first);
  print('[REAL_TEST] favorites seeded count=${_favorites.length}');

  final delegate = DelegateModel(
    uid: _uid,
    firstName: 'TEST Branch Marketing',
    middleName: '',
    lastName: '',
    fullName: 'TEST Branch Marketing',
    nationalityID: '__firebase_auth__:$_email',
    motherName: '',
    city: '',
    phoneNumber: _phone,
    gender: DelegateGender.male,
    position: DelegatePosition.supervisor,
    birthDate: DateTime.now(),
    organizationUID: _org,
    organizationName: '',
    companyUID: '',
    companyName: '',
    status: DelegateStatus.approved,
    delegatePublicId: '',
    allReceiptCodes: const [],
    createdAt: DateTime.now(),
    createdBy: 'test-setup',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    paymentAmount: 0,
    version: 1,
    documents: const [],
    role: UserRole.branchesMarketingManager,
    email: _email,
  );
  await prefs.setString('cachedDelegate', json.encode(delegate.toLocalJson()));
  print('[REAL_TEST] cachedDelegate written');

  unawaited(DelegateOtpConfig.refreshFromRemoteConfig());
  unawaited(AppVersionGate.refresh()); // TAS-66
  try {
    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  } catch (e) {
    debugPrint('Firestore settings config: $e');
  }

  if (!kIsWeb) {
    CrashlyticsService.initialize().catchError((e) {
      debugPrint('Crashlytics Init Error: $e');
    });
  }
  Bloc.observer = AppBlocObserver();
  await di.init(sharedPreferences: prefs);
  localeProvider = di.sl<LocaleProvider>();

  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

  RealTestMetrics.markRunApp();
  print('[REAL_TEST] startup_to_runApp_ms=${DateTime.now().millisecondsSinceEpoch - bootStart}');
  runApp(const MyApp());
}
