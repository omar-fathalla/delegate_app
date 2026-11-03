import 'package:delegate_app/core/services/firestore_client_health.dart';
import 'package:bloc/bloc.dart';
import 'package:delegate_app/core/services/crashlytics_service.dart';
import 'package:flutter/foundation.dart';

/// مراقب عام للـ BLoC يسجل الأخطاء والانتقالات في Crashlytics
class AppBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    FirestoreClientHealth.report(error);

    CrashlyticsService.log('BLoC Error in ${bloc.runtimeType}');
    CrashlyticsService.recordError(
      error,
      stackTrace,
      reason: 'BLoC error in ${bloc.runtimeType}',
    );

    if (kDebugMode) {
      print('🔴 BLoC Error [${bloc.runtimeType}]: $error');
    }
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);

    if (kDebugMode) {
      print(
        '🔄 ${bloc.runtimeType}: '
        '${transition.currentState.runtimeType} → '
        '${transition.nextState.runtimeType}',
      );
    }
  }
}
