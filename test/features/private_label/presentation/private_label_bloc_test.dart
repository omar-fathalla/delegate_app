import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_month_data.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';
import 'package:delegate_app/features/private_label/domain/usecases/cancel_private_label_rest_day.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_cached_private_label_month.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_pending_private_label_audits.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_audits.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_branches.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_month.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_products.dart';
import 'package:delegate_app/features/private_label/domain/usecases/register_private_label_rest_day.dart';
import 'package:delegate_app/features/private_label/domain/usecases/submit_private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/usecases/sync_pending_private_label_audits.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements PrivateLabelRepository {}

final _now = DateTime(2026, 10, 7, 14, 22);
const _org = 'org1';
const _uid = 'u1';

PrivateLabelDay _workedDay(int day, {int audits = 1}) {
  final date = PrivateLabelDates.dayKey(DateTime(2026, 10, day));
  return PrivateLabelDay(
    id: '${_uid}_$date',
    organizationUID: _org,
    companyUID: '',
    delegateUid: _uid,
    delegateName: 'Omar',
    date: date,
    month: '2026-10',
    type: PrivateLabelDayType.worked,
    auditsCount: audits,
  );
}

PrivateLabelDay _restDay(int day) {
  final date = PrivateLabelDates.dayKey(DateTime(2026, 10, day));
  return PrivateLabelDay(
    id: '${_uid}_$date',
    organizationUID: _org,
    companyUID: '',
    delegateUid: _uid,
    delegateName: 'Omar',
    date: date,
    month: '2026-10',
    type: PrivateLabelDayType.rest,
  );
}

PrivateLabelAuditDraft _draft({String id = 'd1', double price = 25}) => PrivateLabelAuditDraft(
      id: id,
      organizationUID: _org,
      companyUID: '',
      delegateUid: _uid,
      delegateName: 'Omar',
      branchName: 'فرع المعادي',
      productName: 'أرز فتح الله 1 كجم',
      shelfPrice: price,
      stockStatus: PrivateLabelStockStatus.available,
      productImagePath: '/tmp/p.jpg',
      priceImagePath: '/tmp/t.jpg',
      capturedAt: _now,
    );

void main() {
  late _MockRepo repo;

  setUpAll(() {
    registerFallbackValue(_draft());
  });

  PrivateLabelBloc buildBloc() => PrivateLabelBloc(
        getCachedMonth: GetCachedPrivateLabelMonth(repo),
        getMonth: GetPrivateLabelMonth(repo),
        submitAudit: SubmitPrivateLabelAudit(repo),
        syncPendingAudits: SyncPendingPrivateLabelAudits(repo),
        getPendingAudits: GetPendingPrivateLabelAudits(repo),
        registerRestDay: RegisterPrivateLabelRestDay(repo),
        cancelRestDay: CancelPrivateLabelRestDay(repo),
        getAudits: GetPrivateLabelAudits(repo),
        getProducts: GetPrivateLabelProducts(repo),
        getBranches: GetPrivateLabelBranches(repo),
        clock: () => _now,
      );

  void stubMonth({
    PrivateLabelMonthData? cached,
    Either<Failure, PrivateLabelMonthData>? fresh,
    List<PrivateLabelAuditDraft> pending = const [],
  }) {
    when(() => repo.getPendingAudits(any())).thenAnswer((_) async => Right(pending));
    when(() => repo.getCachedMonth(
          organizationUID: any(named: 'organizationUID'),
          delegateUid: any(named: 'delegateUid'),
          year: any(named: 'year'),
          month: any(named: 'month'),
        )).thenAnswer((_) async => Right(cached));
    when(() => repo.getMonth(
          organizationUID: any(named: 'organizationUID'),
          delegateUid: any(named: 'delegateUid'),
          year: any(named: 'year'),
          month: any(named: 'month'),
        )).thenAnswer((_) async =>
        fresh ?? const Right(PrivateLabelMonthData(year: 2026, month: 10, days: [], restAllowance: 4)));
  }

  setUp(() {
    repo = _MockRepo();
  });

  const started = PrivateLabelStarted(
    organizationUID: _org,
    companyUID: '',
    delegateUid: _uid,
    delegateName: 'Omar',
    loadDetails: false,
  );

  group('cache-first start', () {
    blocTest<PrivateLabelBloc, PrivateLabelState>(
      'renders cached KPI instantly, then revalidates with server data',
      build: () {
        stubMonth(
          cached: PrivateLabelMonthData(year: 2026, month: 10, days: [_workedDay(1)], restAllowance: 4),
          fresh: Right(PrivateLabelMonthData(
            year: 2026,
            month: 10,
            days: [_workedDay(1), _workedDay(2), _workedDay(7)],
            restAllowance: 5,
          )),
        );
        return buildBloc();
      },
      act: (b) => b.add(started),
      skip: 1, // loading
      expect: () => [
        isA<PrivateLabelState>()
            .having((s) => s.status, 'status', PrivateLabelStatus.ready)
            .having((s) => s.isRefreshing, 'refreshing', true)
            .having((s) => s.kpi?.achievedDays, 'cached achieved', 1),
        isA<PrivateLabelState>()
            .having((s) => s.isRefreshing, 'refreshing', false)
            .having((s) => s.restAllowance, 'allowance', 5)
            .having((s) => s.kpi?.achievedDays, 'fresh achieved', 3)
            .having((s) => s.kpi?.todayStatus, 'today', PrivateLabelTodayStatus.achieved),
      ],
    );

    blocTest<PrivateLabelBloc, PrivateLabelState>(
      'keeps cached data and shows info feedback when offline',
      build: () {
        stubMonth(
          cached: PrivateLabelMonthData(year: 2026, month: 10, days: [_workedDay(3)], restAllowance: 4),
          fresh: const Left(NetworkFailure('offline')),
        );
        return buildBloc();
      },
      act: (b) => b.add(started),
      skip: 2,
      expect: () => [
        isA<PrivateLabelState>()
            .having((s) => s.status, 'status', PrivateLabelStatus.ready)
            .having((s) => s.kpi?.achievedDays, 'achieved', 1)
            .having((s) => s.feedback?.type, 'feedback', PrivateLabelFeedbackType.info),
      ],
    );

    blocTest<PrivateLabelBloc, PrivateLabelState>(
      'offline drafts count toward today immediately',
      build: () {
        stubMonth(pending: [_draft()], fresh: const Left(NetworkFailure('offline')));
        when(() => repo.syncPendingAudits(any())).thenAnswer((_) async => const Left(NetworkFailure('offline')));
        return buildBloc();
      },
      act: (b) => b.add(started),
      verify: (b) {
        expect(b.state.kpi?.todayStatus, PrivateLabelTodayStatus.achieved);
        expect(b.state.pendingDrafts, hasLength(1));
        expect(b.state.dayFor('2026-10-07')?.isLocalOnly, isTrue);
      },
    );
  });

  group('submit', () {
    blocTest<PrivateLabelBloc, PrivateLabelState>(
      'offline submit keeps the draft queued with info feedback',
      build: () {
        stubMonth();
        return buildBloc();
      },
      seed: () => PrivateLabelState(year: 2026, month: 10),
      act: (b) async {
        b.add(started);
        await Future<void>.delayed(Duration.zero);
        when(() => repo.submitAudit(any())).thenAnswer(
          (inv) async => Right(PrivateLabelSubmitResult(
            draft: inv.positionalArguments.first as PrivateLabelAuditDraft,
            synced: false,
          )),
        );
        when(() => repo.getPendingAudits(any())).thenAnswer((_) async => Right([_draft()]));
        b.add(PrivateLabelAuditSubmitted(_draft()));
      },
      wait: const Duration(milliseconds: 50),
      verify: (b) {
        expect(b.state.isSubmitting, isFalse);
        expect(b.state.pendingDrafts, hasLength(1));
        expect(b.state.feedback?.type, PrivateLabelFeedbackType.info);
        expect(b.state.kpi?.todayStatus, PrivateLabelTodayStatus.achieved);
      },
    );

    blocTest<PrivateLabelBloc, PrivateLabelState>(
      'invalid draft (zero price) is rejected before reaching the repository',
      build: () {
        stubMonth();
        return buildBloc();
      },
      act: (b) => b.add(PrivateLabelAuditSubmitted(_draft(price: 0))),
      verify: (b) {
        expect(b.state.feedback?.type, PrivateLabelFeedbackType.error);
        verifyNever(() => repo.submitAudit(any()));
      },
    );
  });

  group('rest days', () {
    blocTest<PrivateLabelBloc, PrivateLabelState>(
      'rejects registering a rest day in the past',
      build: () {
        stubMonth();
        return buildBloc();
      },
      act: (b) async {
        b.add(started);
        await Future<void>.delayed(Duration.zero);
        b.add(const PrivateLabelRestDayRequested('2026-10-01'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (b) {
        expect(b.state.feedback?.type, PrivateLabelFeedbackType.error);
        verifyNever(() => repo.registerRestDay(
              organizationUID: any(named: 'organizationUID'),
              companyUID: any(named: 'companyUID'),
              delegateUid: any(named: 'delegateUid'),
              delegateName: any(named: 'delegateName'),
              date: any(named: 'date'),
              restAllowance: any(named: 'restAllowance'),
            ));
      },
    );

    blocTest<PrivateLabelBloc, PrivateLabelState>(
      'rejects when the monthly allowance is used up',
      build: () {
        stubMonth(
          fresh: Right(PrivateLabelMonthData(
            year: 2026,
            month: 10,
            days: [_restDay(1), _restDay(2), _restDay(3), _restDay(4)],
            restAllowance: 4,
          )),
        );
        return buildBloc();
      },
      act: (b) async {
        b.add(started);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        b.add(const PrivateLabelRestDayRequested('2026-10-07'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (b) {
        expect(b.state.kpi?.remainingRestDays, 0);
        expect(b.state.feedback?.type, PrivateLabelFeedbackType.error);
      },
    );

    blocTest<PrivateLabelBloc, PrivateLabelState>(
      'registering today as rest marks it complete and lowers the balance',
      build: () {
        stubMonth();
        when(() => repo.registerRestDay(
              organizationUID: any(named: 'organizationUID'),
              companyUID: any(named: 'companyUID'),
              delegateUid: any(named: 'delegateUid'),
              delegateName: any(named: 'delegateName'),
              date: any(named: 'date'),
              restAllowance: any(named: 'restAllowance'),
            )).thenAnswer((_) async => Right(_restDay(7)));
        return buildBloc();
      },
      act: (b) async {
        b.add(started);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        b.add(const PrivateLabelRestDayRequested('2026-10-07'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (b) {
        expect(b.state.kpi?.todayStatus, PrivateLabelTodayStatus.rest);
        expect(b.state.kpi?.remainingRestDays, 3);
        expect(b.state.kpi?.completedDays, 1);
        expect(b.state.feedback?.type, PrivateLabelFeedbackType.success);
      },
    );
  });
}
