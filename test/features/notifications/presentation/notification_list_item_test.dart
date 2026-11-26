import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/notifications/presentation/widgets/notification_list_item.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

/// TAS-356: the notification card is a Card.filled with the type icon on
/// primary, and deleting goes through the kit dialog (text buttons, the
/// confirm named after its result): cancel keeps it, delete sends the event.
class _MockBloc extends MockBloc<NotificationEvent, NotificationState>
    implements NotificationBloc {}

class _FakeEvent extends Fake implements NotificationEvent {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeEvent()));

  final delegate = Delegate(
    uid: 'seed-fake-d',
    firstName: 'مندوب',
    middleName: '',
    lastName: 'تجريبي',
    fullName: 'مندوب تجريبي',
    nationalityID: '',
    motherName: '',
    city: '',
    phoneNumber: '01000000000',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    paymentAmount: 0,
    birthDate: DateTime(1990),
    organizationUID: 'org',
    organizationName: 'منظمة',
    companyUID: 'co',
    companyName: 'شركة',
    status: DelegateStatus.active,
    delegatePublicId: '',
    allReceiptCodes: const [],
    createdAt: DateTime(2026),
    createdBy: 'seed',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    version: 1,
    documents: const [],
    role: UserRole.delegate,
  );

  final notification = NotificationEntity(
    id: 'n1',
    delegateUid: 'seed-fake-d',
    organizationId: 'org',
    companyId: 'co',
    title: 'إشعار تجريبي',
    body: 'نص الإشعار',
    type: 'penalty',
    isRead: false,
    createdAt: DateTime(2026, 11, 26, 10),
  );

  late _MockBloc bloc;

  Future<void> pump(WidgetTester t) async {
    bloc = _MockBloc();
    when(() => bloc.state).thenReturn(NotificationInitial());
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: BlocProvider<NotificationBloc>.value(
            value: bloc,
            child: NotificationListItem(
              notification: notification,
              delegate: delegate,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('card: Card.filled, type icon on primary, unread dot', (t) async {
    await pump(t);
    expect(find.byType(Card), findsOneWidget);
    final cs = Theme.of(t.element(find.byType(Card))).colorScheme;
    final icon = t.widget<Icon>(find.byIcon(Icons.gavel_rounded));
    expect(icon.color, cs.onPrimary);
    expect(find.byKey(const Key('notificationUnreadDot')), findsOneWidget);
  });

  testWidgets('delete opens the kit dialog; cancel keeps it', (t) async {
    await pump(t);
    await t.tap(find.byTooltip('حذف الإشعار').first);
    await t.pumpAndSettle();
    final dialog = find.byKey(const Key('deleteNotificationDialog'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(FilledButton)),
      findsNothing,
    );
    await t.tap(find.descendant(of: dialog, matching: find.byType(TextButton)).first);
    await t.pumpAndSettle();
    expect(dialog, findsNothing);
    verifyNever(() => bloc.add(any(that: isA<DeleteNotificationRequested>())));
  });

  testWidgets('confirm sends DeleteNotificationRequested', (t) async {
    await pump(t);
    await t.tap(find.byTooltip('حذف الإشعار').first);
    await t.pumpAndSettle();
    final dialog = find.byKey(const Key('deleteNotificationDialog'));
    await t.tap(find.descendant(of: dialog, matching: find.byType(TextButton)).last);
    await t.pumpAndSettle();
    verify(() => bloc.add(any(that: isA<DeleteNotificationRequested>()))).called(1);
  });
}
