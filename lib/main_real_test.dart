// ignore_for_file: avoid_print
/// Local/real-test entrypoint. Not used by release builds.
///
/// Example:
/// flutter run -t lib/main_real_test.dart -d emulator-5554 \
///   --dart-define=REAL_TEST_CUSTOM_TOKEN=... \
///   --dart-define=REAL_TEST_START_BRANCH_TAB=true
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/services/app_bloc_observer.dart';
import 'package:delegate_app/core/services/crashlytics_service.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/firebase_options.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/main.dart' show MyApp, localeProvider;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _token = String.fromEnvironment('REAL_TEST_CUSTOM_TOKEN');
const _uid = 'O0LHjrZU7TXG5LHi9QcqavE4i1q1';
const _email = 'probe.tashil.test1@gmail.com';
const _org = 'PiioBFgxaHAeuRdjlDgj';
const _phone = '01555550001';
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
  GoogleFonts.config.allowRuntimeFetching = false;

  if (_token.isEmpty) {
    throw StateError('REAL_TEST_CUSTOM_TOKEN dart-define is required');
  }

  final results = await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    SharedPreferences.getInstance(),
  ]);
  final prefs = results[1] as SharedPreferences;

  print('[REAL_TEST] signing in with custom token…');
  final cred = await FirebaseAuth.instance.signInWithCustomToken(_token);
  print('[REAL_TEST] auth.uid=${cred.user?.uid}');

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

  print('[REAL_TEST] runApp');
  runApp(const MyApp());
}
