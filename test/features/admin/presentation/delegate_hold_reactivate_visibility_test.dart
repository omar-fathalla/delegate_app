import 'package:delegate_app/core/security/delegate_status_policy.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('إعادة تفعيل hidden for suspended delegate when viewer is admin', (tester) async {
  final show = delegateHoldShowsReactivate(
      canSetHold: true,
      delegateSuspended: true,
      viewerRole: UserRole.admin,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: show
              ? const Text('إعادة تفعيل')
              : const Text('no-reactivate'),
        ),
      ),
    );
    expect(find.text('إعادة تفعيل'), findsNothing);
    expect(find.text('no-reactivate'), findsOneWidget);
  });

  testWidgets('إعادة تفعيل visible for suspended delegate when viewer is technical support', (tester) async {
    final show = delegateHoldShowsReactivate(
      canSetHold: true,
      delegateSuspended: true,
      viewerRole: UserRole.technicalSupport,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: show
              ? const Text('إعادة تفعيل')
              : const Text('no-reactivate'),
        ),
      ),
    );
    expect(find.text('إعادة تفعيل'), findsOneWidget);
  });
}