import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// TAS-354: «active delegates» and «by delegate» are for the manager view
/// (supervisor, admin, HR, marketing). A field delegate only sees their own
/// photos, so both are hidden for them [UI only]. Grouping is a connected
/// ButtonGroup. Fake data only.
class _MockPhotoBloc extends MockBloc<PhotoPermissionEvent, PhotoPermissionState>
    implements PhotoPermissionBloc {}

class _FakePhotoEvent extends Fake implements PhotoPermissionEvent {}

Delegate _user({UserRole role = UserRole.delegate, DelegatePosition position = DelegatePosition.promoter}) => Delegate(
  uid: 'seed-fake-u',
  firstName: 'مستخدم',
  middleName: '',
  lastName: 'تجريبي',
  fullName: 'مستخدم تجريبي',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: position,
  birthDate: DateTime(1995),
  organizationUID: 'seed-fake-org',
  organizationName: 'منظمة تجريبية',
  // Empty: the header's company-code lookup skips Firestore in tests.
  companyUID: '',
  companyName: 'شركة تجريبية',
  status: DelegateStatus.active,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2024),
  createdBy: 'seed',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: role,
);

void main() {
  setUpAll(() => registerFallbackValue(_FakePhotoEvent()));

  Future<AppLocalizations> pump(WidgetTester t, Delegate who) async {
    final bloc = _MockPhotoBloc();
    whenListen(
      bloc,
      const Stream<PhotoPermissionState>.empty(),
      initialState: const CapturedPhotosLoaded(photos: []),
    );
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: BlocProvider<PhotoPermissionBloc>.value(
          value: bloc,
          child: MonthlyPhotoReportScreen(delegate: who, showAppBar: false),
        ),
      ),
    );
    await t.pump();
    return lookupAppLocalizations(const Locale('ar'));
  }

  testWidgets('field delegate: no active delegates, no by-delegate', (t) async {
    final l10n = await pump(t, _user());
    expect(find.byType(ButtonGroup<GroupMode>), findsOneWidget);
    expect(find.text(l10n.byDate), findsOneWidget);
    expect(find.text(l10n.byBranch), findsOneWidget);
    expect(find.text(l10n.byDelegate), findsNothing);
    expect(find.text(l10n.activeDelegates), findsNothing);
  });

  for (final (name, who) in [
    ('supervisor', _user(position: DelegatePosition.supervisor)),
    ('hr', _user(role: UserRole.hr)),
    ('admin', _user(role: UserRole.admin)),
    ('marketing', _user(role: UserRole.marketing)),
  ]) {
    testWidgets('$name: sees active delegates and by-delegate', (t) async {
      final l10n = await pump(t, who);
      expect(find.text(l10n.byDelegate), findsOneWidget);
      expect(find.text(l10n.activeDelegates), findsOneWidget);
    });
  }
}
