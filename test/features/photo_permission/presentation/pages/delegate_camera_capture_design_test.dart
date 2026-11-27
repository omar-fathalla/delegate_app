import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/delegate_camera_capture_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

/// TAS-387 (user review 27 Nov 2026): «تصوير العروض» in two steps. Step 1:
/// the chain, then a branch of it (DropdownMenus) and the permission facts;
/// step 2: the photos. One branch is picked by itself. No permission is an
/// EmptyState. Fake data only.
class _MockPhotoBloc
    extends MockBloc<PhotoPermissionEvent, PhotoPermissionState>
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
  companyUID: 'seed-fake-co',
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

PhotoPermission _perm(List<String> branches) => PhotoPermission(
  uid: 'seed-fake-pp',
  organizationUID: 'seed-fake-org',
  companyUID: 'seed-fake-co',
  companyName: 'شركة تجريبية',
  branchIds: [for (var i = 0; i < branches.length; i++) 'b$i'],
  branchNames: branches,
  startDate: DateTime(2026, 11, 1),
  endDate: DateTime(2026, 11, 30),
  status: 'approved',
  requestedBy: 'seed',
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  isSupervisorEnabled: false,
);

void main() {
  setUpAll(() => registerFallbackValue(_FakePhotoEvent()));

  Future<AppLocalizations> pump(WidgetTester t, PhotoPermissionState s) async {
    final bloc = _MockPhotoBloc();
    whenListen(bloc, const Stream<PhotoPermissionState>.empty(), initialState: s);
    t.view.physicalSize = const Size(420, 2400);
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
          child: DelegateCameraCaptureScreen(delegate: _user()),
        ),
      ),
    );
    await t.pump();
    return lookupAppLocalizations(const Locale('ar'));
  }

  testWidgets('step 1: chain, then branch; step 2 waits for a branch', (t) async {
    final l10n = await pump(
      t,
      OngoingPermissionsLoaded(permissions: [_perm(['فرع أ', 'فرع ب'])]),
    );
    expect(find.byKey(const Key('photo_chain_menu')), findsOneWidget);
    expect(find.text(l10n.captureStepPlace), findsOneWidget);
    expect(find.text(l10n.captureStepPhotos), findsOneWidget);
    expect(find.byKey(const Key('capture_choose_branch_first')), findsOneWidget);
    expect(find.byKey(const Key('capture_first_photo')), findsNothing);
  });

  testWidgets('one branch is picked by itself and the camera tile shows', (t) async {
    await pump(t, OngoingPermissionsLoaded(permissions: [_perm(['فرع أ'])]));
    expect(find.byKey(const Key('capture_first_photo')), findsOneWidget);
  });

  testWidgets('no permission: EmptyState', (t) async {
    final l10n = await pump(t, const OngoingPermissionsLoaded(permissions: []));
    expect(find.byType(EmptyState), findsWidgets);
    expect(find.text(l10n.noPhotoPermissions), findsOneWidget);
  });

  testWidgets('loading: skeletons', (t) async {
    await pump(t, PhotoPermissionLoading());
    expect(find.byKey(const Key('capture_skeleton')), findsOneWidget);
  });
}
