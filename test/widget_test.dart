import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';

// Manual mock for AuthBloc to avoid complex dependency injection in smoke test
class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc() : super(AuthInitial());

  @override
  Login get loginUseCase => throw UnimplementedError();
}

void main() {
  setUp(() {
    // Configure GetIt to allow reassignment for testing
    sl.allowReassignment = true;
    sl.registerFactory<AuthBloc>(() => MockAuthBloc());
  });

  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the login screen elements are present.
    // 'Tasheel Delegate' is the main title on the Login Screen.
    expect(find.text('Tasheel Delegate'), findsOneWidget);
    // 'LOGIN' is the text on the elevated button.
    expect(find.text('LOGIN'), findsOneWidget);
    // 'Mobile Number' is the label text for the first TextFormField.
    expect(find.text('Mobile Number'), findsOneWidget);
  });
}
