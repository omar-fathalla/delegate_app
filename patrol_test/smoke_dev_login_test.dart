import 'package:delegate_app/main.dart' show MyApp, bootstrapDelegateAppForPatrol;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'dev flavor: splash stall sign in login screen visible',
    ($) async {
      await bootstrapDelegateAppForPatrol();
      await $.pumpWidget(const MyApp());

      expect(Firebase.app().options.projectId, 'tashil-dev');

      final loginField = const Key('login_phone_field');
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline)) {
        await $.tester.pump(const Duration(milliseconds: 500));
        if ($(loginField).exists) break;
        final signIn = $(const Key('splash_sign_in'));
        if (signIn.exists) {
          await signIn.tap();
          await $.tester.pumpAndSettle(const Duration(seconds: 2));
          if ($(loginField).exists) break;
        }
      }

      await $(loginField).waitUntilVisible(
        timeout: const Duration(seconds: 15),
      );
      expect($(loginField), findsOneWidget);
    },
  );
}
