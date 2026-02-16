import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart';

// Manual mock for AuthBloc
class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc() : super(AuthInitial());

  @override
  Login get loginUseCase => throw UnimplementedError();
}

void main() {
  setUp(() {
    sl.allowReassignment = true;
    if (!sl.isRegistered<AuthBloc>()) {
      sl.registerFactory<AuthBloc>(() => MockAuthBloc());
    }
  });

  testWidgets('LoginScreen disposes correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Interact with text fields to ensure controllers are active
    await tester.enterText(find.byType(TextFormField).at(0), '1234567890');
    await tester.enterText(find.byType(TextFormField).at(1), 'MotherName');

    // Verify text is entered
    expect(find.text('1234567890'), findsOneWidget);
    expect(find.text('MotherName'), findsOneWidget);

    // Pump another widget to trigger disposal of LoginScreen
    await tester.pumpWidget(const SizedBox());

    // No specific assertion for disposal here as we are relying on no exceptions being thrown.
  });
}
