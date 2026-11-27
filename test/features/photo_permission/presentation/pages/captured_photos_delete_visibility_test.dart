// TAS-402: branch marketing may not delete field photos, so the photos screen
// hides its delete controls when canDeletePhotos is false.
import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/captured_photos_view_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class _MockPhotoBloc extends MockBloc<PhotoPermissionEvent, PhotoPermissionState>
    implements PhotoPermissionBloc {}

class _FakePhotoEvent extends Fake implements PhotoPermissionEvent {}

void main() {
  setUpAll(() => registerFallbackValue(_FakePhotoEvent()));

  final now = DateTime(2026, 11, 27, 10);
  final permission = PhotoPermission(
    uid: 'perm-1',
    organizationUID: 'org',
    companyUID: 'co',
    companyName: 'Fake Company Alpha',
    branchIds: const ['br'],
    branchNames: const ['Fake Branch Alpha'],
    startDate: now,
    endDate: now.add(const Duration(days: 10)),
    status: 'approved',
    requestedBy: 'seed',
    createdAt: now,
    updatedAt: now,
    isSupervisorEnabled: true,
  );
  final photo = CapturedPhoto(
    uid: 'photo-1',
    permissionId: 'perm-1',
    organizationUID: 'org',
    companyUID: 'co',
    branchId: 'br',
    branchName: 'Fake Branch Alpha',
    delegateUID: 'del-1',
    delegateName: 'Fake Delegate alpha 1',
    photoUrl: '',
    comment: '',
    latitude: 0,
    longitude: 0,
    capturedAt: now,
  );

  Future<void> pump(WidgetTester t, {required bool canDelete}) async {
    final bloc = _MockPhotoBloc();
    whenListen(
      bloc,
      const Stream<PhotoPermissionState>.empty(),
      initialState: CapturedPhotosLoaded(photos: [photo]),
    );
    t.view.physicalSize = const Size(400, 1600);
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
          child: CapturedPhotosViewScreen(
            photoPermission: permission,
            canDeletePhotos: canDelete,
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('delete control shows when deleting is allowed', (t) async {
    await pump(t, canDelete: true);
    expect(find.byIcon(Icons.delete_outline_rounded), findsWidgets);
  });

  testWidgets('no delete control for branch marketing (TAS-402)', (t) async {
    await pump(t, canDelete: false);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
  });
}
