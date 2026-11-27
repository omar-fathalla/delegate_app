import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/services/sync_manager.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_offline_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:mocktail/mocktail.dart';

class _MockRemote extends Mock implements PhotoPermissionRemoteDataSource {}

class _EmptyQueue extends PhotoOfflineDataSource {
  @override
  Future<List<Map<String, dynamic>>> getPendingPhotosForDelegates(Set<String> ids) async => const [];
}

/// TAS-350 (m3-kit C-27): the logout confirmation is a basic M3 AlertDialog,
/// not a bottom sheet: question as the headline, two text buttons, cancel
/// first and the confirm (named after its result) at the end, which is the
/// left in Arabic.
void main() {
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

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    AppLogoutModal.show(context, delegate: delegate),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('opens an AlertDialog, not a bottom sheet', (t) async {
    await open(t);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('تسجيل الخروج؟'), findsOneWidget);
    expect(find.text('بياناتك المحلية هتتحفظ قبل الخروج'), findsOneWidget);
  });

  testWidgets('cancel first, confirm at the end (left in RTL)', (t) async {
    await open(t);
    final cancel = t.getRect(find.widgetWithText(TextButton, 'إلغاء'));
    final confirm = t.getRect(find.widgetWithText(TextButton, 'تسجيل الخروج'));
    expect(confirm.center.dx, lessThan(cancel.center.dx));
    // Both are text buttons (no filled or connected button group).
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('cancel closes the dialog without logging out', (t) async {
    await open(t);
    await t.tap(find.widgetWithText(TextButton, 'إلغاء'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('TAS-369: photos still on the phone -> warning, «استنى» and «اخرج برضه»', (t) async {
    final sync = SyncManager(
      offlineDataSource: _EmptyQueue(),
      remoteDataSource: _MockRemote(),
      isBackground: true,
      selfIds: () => {'seed-fake-d'},
    );
    sl.registerSingleton<SyncManager>(sync);
    addTearDown(() => sl.unregister<SyncManager>());
    await t.pump();
    sync.statusNotifier.value = const SyncState(pendingCount: 3);
    await open(t);
    expect(find.byKey(const Key('logout_pending_photos_warning')), findsOneWidget);
    expect(find.textContaining('3 صور لسه على الموبايل'), findsOneWidget);
    expect(find.text('استنى'), findsOneWidget);
    expect(find.text('اخرج برضه'), findsOneWidget);
  });
}
