import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/captured_photo.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/photo_details_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

/// TAS-387 (user review 27 Nov 2026): the photo report follows the
/// playground. One month card with the numbers, a 3-column grid per group,
/// a badge only on photos still on the phone, a details page opened from the
/// photo, skeletons while loading, EmptyState for empty. Fake data only.
class _MockPhotoBloc
    extends MockBloc<PhotoPermissionEvent, PhotoPermissionState>
    implements PhotoPermissionBloc {}

class _FakePhotoEvent extends Fake implements PhotoPermissionEvent {}

Delegate _user({UserRole role = UserRole.delegate}) => Delegate(
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
  position: DelegatePosition.promoter,
  birthDate: DateTime(1995),
  organizationUID: 'seed-fake-org',
  organizationName: 'منظمة تجريبية',
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

CapturedPhoto _photo(
  String uid,
  DateTime at, {
  String branch = 'فرع تجريبي',
  double lat = 0,
}) =>
    CapturedPhoto(
      uid: uid,
      permissionId: 'seed-fake-p',
      organizationUID: 'seed-fake-org',
      companyUID: 'seed-fake-co',
      branchId: branch,
      branchName: branch,
      delegateUID: 'seed-fake-u',
      delegateName: 'مستخدم تجريبي',
      photoUrl: '',
      comment: 'تعليق تجريبي',
      latitude: lat,
      longitude: lat,
      capturedAt: at,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_FakePhotoEvent());
    PhotoDetailsPage.mapPreviewEnabled = false;
  });

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10);

  Future<AppLocalizations> pump(
    WidgetTester t,
    PhotoPermissionState state, {
    Delegate? who,
  }) async {
    final bloc = _MockPhotoBloc();
    whenListen(
      bloc,
      const Stream<PhotoPermissionState>.empty(),
      initialState: state,
    );
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
          child: MonthlyPhotoReportScreen(
            delegate: who ?? _user(),
            showAppBar: false,
          ),
        ),
      ),
    );
    await t.pump();
    return lookupAppLocalizations(const Locale('ar'));
  }

  testWidgets('loading shows skeletons, not a placeholder 0', (t) async {
    await pump(t, PhotoPermissionLoading());
    expect(find.byKey(const Key('photo_month_card')), findsOneWidget);
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('photos are a grid under each group; only pending has a badge',
      (t) async {
    await pump(
      t,
      CapturedPhotosLoaded(
        photos: [
          _photo('a', today),
          _photo('b', today),
          _photo('pending_c', today.subtract(const Duration(hours: 1))),
        ],
      ),
    );
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_tile_a')), findsOneWidget);
    expect(find.byKey(const Key('photo_pending_pending_c')), findsOneWidget);
    expect(find.byKey(const Key('photo_pending_a')), findsNothing);
    expect(find.text('3'), findsOneWidget); // total photos
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('a photo opens its details page: toolbar, list, comment',
      (t) async {
    final l10n = await pump(
      t,
      CapturedPhotosLoaded(photos: [_photo('a', today, lat: 30)]),
    );
    await t.tap(find.byKey(const ValueKey('photo_tile_a')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('photo_details_pager')), findsOneWidget);
    expect(find.text(l10n.photoDetails), findsOneWidget);
    expect(find.byKey(const Key('photo_details_toolbar')), findsOneWidget);
    expect(find.byKey(const Key('photo_details_comment')), findsOneWidget);
    expect(find.byKey(const Key('photo_details_map_chip')), findsOneWidget);
    expect(find.byKey(const Key('photo_details_time')), findsOneWidget);
    // A field delegate cannot delete; one photo has no counter.
    expect(find.byKey(const Key('photo_details_menu')), findsNothing);
    expect(find.byKey(const Key('photo_details_counter')), findsNothing);
  });

  testWidgets('swipe moves to the next photo and the counter follows',
      (t) async {
    await pump(
      t,
      CapturedPhotosLoaded(
        photos: [
          _photo('a', today),
          _photo('b', today.subtract(const Duration(minutes: 5))),
        ],
      ),
    );
    await t.tap(find.byKey(const ValueKey('photo_tile_a')));
    await t.pumpAndSettle();
    final counter = find.byKey(const Key('photo_details_counter'));
    expect(t.widget<Text>(counter).data, contains('1'));
    // RTL: the next page is to the left, so drag to the right.
    await t.fling(
      find.byKey(const Key('photo_details_pager')),
      const Offset(300, 0),
      1000,
    );
    await t.pumpAndSettle();
    expect(t.widget<Text>(counter).data, contains('2'));
  });

  testWidgets('tapping the photo hides everything else, tapping again '
      'brings it back', (t) async {
    await pump(t, CapturedPhotosLoaded(photos: [_photo('a', today)]));
    await t.tap(find.byKey(const ValueKey('photo_tile_a')));
    await t.pumpAndSettle();
    final photo = find.bySemanticsLabel(RegExp('فرع تجريبي'));
    await t.tap(photo.first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('photo_details_immersive')), findsOneWidget);
    expect(find.byKey(const Key('photo_details_toolbar')), findsNothing);
    await t.tap(find.bySemanticsLabel(RegExp('فرع تجريبي')).first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('photo_details_toolbar')), findsOneWidget);
  });

  testWidgets('a photo still on the phone shows the banner', (t) async {
    final l10n = await pump(
      t,
      CapturedPhotosLoaded(photos: [_photo('pending_x', today)]),
    );
    await t.tap(find.byKey(const ValueKey('photo_tile_pending_x')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('photo_details_pending_banner')),
      findsOneWidget,
    );
    await t.tap(find.text(l10n.photoBannerOk));
    await t.pump();
    expect(
      find.byKey(const Key('photo_details_pending_banner')),
      findsNothing,
    );
  });

  testWidgets('a manager deletes from the ⋮ menu through the kit dialog',
      (t) async {
    await pump(
      t,
      CapturedPhotosLoaded(photos: [_photo('a', today)]),
      who: _user(role: UserRole.hr),
    );
    await t.tap(find.byKey(const ValueKey('photo_tile_a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('photo_details_menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('photo_details_delete')));
    await t.pumpAndSettle();
    final dialog = find.byKey(const Key('photo_delete_dialog'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(FilledButton)),
      findsNothing,
    );
  });

  testWidgets('empty month: EmptyState with a capture action', (t) async {
    final l10n = await pump(t, const CapturedPhotosLoaded(photos: []));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text(l10n.photosCaptureAction), findsOneWidget);
  });

  testWidgets('a manager has no capture action on an empty month', (t) async {
    final l10n = await pump(
      t,
      const CapturedPhotosLoaded(photos: []),
      who: _user(role: UserRole.hr),
    );
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text(l10n.photosCaptureAction), findsNothing);
  });
}
