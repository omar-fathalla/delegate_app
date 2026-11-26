import 'package:delegate_app/core/logging/release_log_guard.dart';
import 'package:delegate_app/core/services/firestore_cache_reset.dart';
import 'dart:async';

import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/services/app_check_bootstrap.dart';
import 'package:delegate_app/core/services/crashlytics_service.dart';
import 'package:delegate_app/core/services/app_bloc_observer.dart';
import 'package:delegate_app/core/services/firestore_client_health.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/core/services/task_push_route.dart';
import 'package:delegate_app/core/services/web_path_to_hash.dart';
import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/core/time/cairo_clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show appFlavor;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/config/routes/app_router.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/core/services/app_version_gate.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/core/services/sync_manager.dart';
import 'l10n/app_localizations_delegates.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint("Native called background task: $task");
      WidgetsFlutterBinding.ensureInitialized();

      return await Future.sync(() async {
        await Firebase.initializeApp(options: AppEnv.firebaseOptions)
            .timeout(const Duration(seconds: 8));
        // TAS-16: App Check, monitoring only; never blocks the task.
        activateAppCheckMonitoring();
        await di.initBackgroundSync();

        final syncManager = di.sl<SyncManager>();
        await syncManager.syncPendingPhotos();
        return true;
      }).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint("Background sync exceeded 25s timeout - completing task to prevent ANR.");
          return false;
        },
      );
    } catch (err) {
      debugPrint("Background sync error: $err");
      return false;
    }
  });
}

/// Top-level background message handler for FCM.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: AppEnv.firebaseOptions);
  // Background messages are displayed automatically by the system tray.
  debugPrint('FCM background message: ${message.notification?.title}');
}

/// Global providers accessible throughout the app.
late final LocaleProvider localeProvider;

bool _delegateAppBootstrapped = false;

/// Minimal startup for Patrol (`patrol_test/`) entrypoints that do not run [main].
Future<void> bootstrapDelegateAppForPatrol() async {
  if (_delegateAppBootstrapped) return;
  _delegateAppBootstrapped = true;

  WidgetsFlutterBinding.ensureInitialized();
  CairoClock.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  // M3 design system: Latin digits in Arabic locales (dates, numbers).
  DateFormat.useNativeDigitsByDefaultFor('ar', false);

  // TAS-221: flavor and ENV must match before anything talks to Firebase.
  AppEnv.verifyFlavor(appFlavor);

  final results = await Future.wait([
    Firebase.initializeApp(options: AppEnv.firebaseOptions),
    SharedPreferences.getInstance(),
  ]);

  // TAS-16: App Check in monitoring mode (nothing enforced). Fire-and-forget;
  // errors are swallowed so startup never waits on or fails because of it.
  activateAppCheckMonitoring();

  if (AppEnv.isDev) {
    debugPrint('GIT_SHA=${AppEnv.gitSha}');
    AppEnv.verifyFirebaseProject(Firebase.app().options.projectId);
  }

  unawaited(DelegateOtpConfig.refreshFromRemoteConfig());
  // TAS-66: forced-update decision; the splash waits for it before login.
  unawaited(AppVersionGate.refresh());

  // TAS-76: a logout on this device asked to drop the previous user's
  // cache; do it before anything reads Firestore in this run.
  // TAS-244: once per device, also drop a cache left by an older build.
  if (!kIsWeb) {
    final cacheReset =
        FirestoreCacheReset(prefs: results[1] as SharedPreferences);
    await cacheReset.markLegacyCacheOnce();
    await cacheReset.runIfPending();
  }

  try {
    if (!kIsWeb) {
      // TAS-76: bounded disk cache (was unlimited) on shared devices.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024,
      );
    }
  } catch (e) {
    debugPrint('Firestore settings config: $e');
  }

  Bloc.observer = AppBlocObserver();
  final sharedPreferences = results[1] as SharedPreferences;
  await di.init(sharedPreferences: sharedPreferences);
  localeProvider = di.sl<LocaleProvider>();

  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;
}

void main() async {
  // TAS-83: no debugPrint output (phones, uids) in release builds.
  silenceDebugPrintInRelease();

  // TAS-197: `/hr/home` → `/#/hr/home` before the router reads the address.
  normalizeWebPathToHash();

  if (!_delegateAppBootstrapped) {
    await bootstrapDelegateAppForPatrol();
  }

  if (!kIsWeb) {
    // Register background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize Crashlytics non-blockingly
    CrashlyticsService.initialize().catchError((e) {
      debugPrint('Crashlytics Init Error: $e');
    });
  }

  if (kIsWeb) {
    // Catch the Firestore JS SDK assert (ca9/b815) and show a reload banner
    // instead of blank tabs. Chains any existing handler.
    final previous = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final handled = FirestoreClientHealth.report(error);
      return (previous?.call(error, stack) ?? false) || handled;
    };
  }

  // Set up notification tap handler for navigation
  PushNotificationService.onNotificationTap = (data) {
    final route = taskPushRoute(data);
    if (route == null) return;
    debugPrint('Notification tapped: opening $route');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        appRouter.go(route);
      } catch (e) {
        debugPrint('Notification tap navigation error: $e');
      }
    });
  };

  // Note: FCM initialization is now done post-login in SplashScreen/LoginScreen
  // so we have the delegate UID for token storage.

  runApp(const MyApp());

  // Schedule background tasks non-blockingly after UI has launched
  _scheduleBackgroundSync();
}

/// Schedules background sync safely after UI has settled, avoiding main-thread contention during boot.
void _scheduleBackgroundSync() {
  if (kIsWeb) return;
  Future.delayed(const Duration(seconds: 8), () {
    try {
      Workmanager().initialize(
        callbackDispatcher,
      );
      Workmanager().registerPeriodicTask(
        "offlineSyncTask",
        "offlineSyncTask",
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 2),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } catch (e) {
      debugPrint('Workmanager init error: $e');
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    localeProvider.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    localeProvider.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => di.sl<ThemeCubit>()),
        BlocProvider(create: (_) => di.sl<AuthBloc>()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp.router(
            title: 'Tashil Employee',
            theme: AppTheme.lightTheme(themeState.seedColor),
            darkTheme: AppTheme.darkTheme(themeState.seedColor),
            highContrastTheme: AppTheme.highContrastLightTheme(
              themeState.seedColor,
            ),
            highContrastDarkTheme: AppTheme.highContrastDarkTheme(
              themeState.seedColor,
            ),
            themeMode: themeState.themeMode,
            routerConfig: appRouter,
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              final content = !isProduction
                  ? Banner(
                      message: 'TEST ENV',
                      location: BannerLocation.topStart,
                      color: Theme.of(context).colorScheme.error,
                      child: child!,
                    )
                  : child!;
              final shown = AppEnv.isDev
                  ? Banner(
                      message: 'DEV',
                      location: BannerLocation.topEnd,
                      color: Colors.deepPurple,
                      child: content,
                    )
                  : content;
              return BlocListener<AuthBloc, AuthState>(
                listener: (context, state) {
                  if (state is AuthUnauthenticated && state.fromLogout) {
                    final path =
                        appRouter.routeInformationProvider.value.uri.path;
                    if (path != '/login' && path != '/hr/login') {
                      appRouter.go('/login');
                    }
                    return;
                  }
                  if (state is! AuthUnauthenticated ||
                      state.message != AuthBloc.freshSignInMessage) {
                    return;
                  }
                  final path =
                      appRouter.routeInformationProvider.value.uri.path;
                  if (path != '/login' && path != '/hr/login') {
                    appRouter.go('/login');
                  }
                  final message = state.message!;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final navContext =
                        appRouter.routerDelegate.navigatorKey.currentContext;
                    if (navContext == null || !navContext.mounted) return;
                    ScaffoldMessenger.of(navContext).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        duration: const Duration(seconds: 5),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  });
                },
                child: FirestoreClientHealthBanner(child: shown),
              );
            },
            locale: localeProvider.locale,
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
          );
        },
      ),
    );
  }
}
