import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/data/services/branch_attendance_qr_service.dart';
import 'package:delegate_app/features/admin/domain/usecases/add_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_branches.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_branch.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/admin/presentation/pages/branch_details_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class _Get extends Mock implements GetBranches {}

class _Add extends Mock implements AddBranch {}

class _Update extends Mock implements UpdateBranch {}

class _Delete extends Mock implements DeleteBranch {}

class _FakeQrService implements BranchAttendanceQrService {
  int version = 0;
  final calls = <bool>[];

  @override
  Future<BranchAttendanceQr> fetch({
    required String branchId,
    required String organizationUID,
    bool regenerate = false,
  }) async {
    calls.add(regenerate);
    if (regenerate) version++;
    return BranchAttendanceQr(
      version: version,
      payload: version == 0
          ? null
          : {
              'type': 'attendance',
              'v': 2,
              'branchId': branchId,
              'organizationUID': organizationUID,
              'qrVersion': version,
              'sig': 'test',
            },
    );
  }
}

/// TAS-372: the branch screen shows the signed QR and regenerates it.
void main() {
  setUp(() {
    if (di.sl.isRegistered<BranchBloc>()) di.sl.unregister<BranchBloc>();
    di.sl.registerFactory<BranchBloc>(
      () => BranchBloc(
        getBranches: _Get(),
        addBranch: _Add(),
        updateBranch: _Update(),
        deleteBranch: _Delete(),
      ),
    );
  });

  tearDown(() => di.sl.unregister<BranchBloc>());

  testWidgets('old QR first, then a confirmed regenerate shows version 1', (
    tester,
  ) async {
    final service = _FakeQrService();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BranchDetailsScreen(
          qrService: service,
          branch: const BranchModel(
            id: 'b1',
            branchName: 'Fake Alpha',
            latitude: 30.0,
            longitude: 31.0,
            geofenceRadius: 100,
            organizationUID: 'o1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.calls, [false]);
    expect(find.textContaining('كود قديم من غير توقيع'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('branchQr.regenerate')));
    await tester.tap(find.byKey(const Key('branchQr.regenerate')));
    await tester.pumpAndSettle();
    expect(find.text('تعمل كود حضور جديد؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('branchQr.confirmRegenerate')));
    await tester.pumpAndSettle();

    expect(service.calls, [false, true]);
    expect(find.text('كود موقّع، الإصدار 1'), findsOneWidget);
  });
}
