import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/splash_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  late MockAuthBloc bloc;
  final defaultStall = SplashScreen.stallTimeout;

  setUpAll(() => registerFallbackValue(CheckAutoLoginRequested()));

  setUp(() {
    bloc = MockAuthBloc();
    whenListen(bloc, const Stream<AuthState>.empty(), initialState: AuthLoading());
    SplashScreen.stallTimeout = const Duration(seconds: 12);
  });

  tearDown(() => SplashScreen.stallTimeout = defaultStall);

  Future<void> pumpSplash(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('LOGIN_PAGE')),
        ),
      ],
    );
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('no fallback before 12s; fallback after', (tester) async {
    await pumpSplash(tester);
    await tester.pump(const Duration(seconds: 11));
    expect(find.byKey(const Key('splash_retry')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('تعذّر الاتصال'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });

  testWidgets('retry re-dispatches CheckAutoLoginRequested', (tester) async {
    await pumpSplash(tester);
    await tester.pump(const Duration(seconds: 13));
    await tester.tap(find.byKey(const Key('splash_retry')));
    await tester.pump();
    verify(() => bloc.add(any(that: isA<CheckAutoLoginRequested>())))
        .called(2);
    expect(find.byKey(const Key('splash_retry')), findsNothing);
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets('sign-in button dispatches AutoLoginCancelled', (tester) async {
    await pumpSplash(tester);
    await tester.pump(const Duration(seconds: 13));
    await tester.tap(find.byKey(const Key('splash_sign_in')));
    await tester.pump();
    verify(() => bloc.add(any(that: isA<AutoLoginCancelled>()))).called(1);
  });

  testWidgets('goes to /login when cancel emits Unauthenticated',
      (tester) async {
    final ctrl = StreamController<AuthState>();
    whenListen(bloc, ctrl.stream, initialState: AuthLoading());
    await pumpSplash(tester);
    await tester.pump(const Duration(seconds: 13));
    await tester.tap(find.byKey(const Key('splash_sign_in')));
    ctrl.add(const AuthUnauthenticated());
    await tester.pumpAndSettle();
    expect(find.text('LOGIN_PAGE'), findsOneWidget);
    await ctrl.close();
  });
}
