import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_organization_private_label_days.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_branches.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_report_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements PrivateLabelRepository {}

void main() {
  late _MockRepo repo;
  late GetOrganizationPrivateLabelDays getOrgMonthDays;
  late GetPrivateLabelBranches getBranches;

  final sampleDay1 = const PrivateLabelDay(
    id: 'u1_2026-10-01',
    organizationUID: 'org1',
    companyUID: 'comp1',
    delegateUid: 'u1',
    delegateName: 'Sobhy Kassem',
    date: '2026-10-01',
    month: '2026-10',
    type: PrivateLabelDayType.worked,
    auditsCount: 5,
    rejectedCount: 0,
    branchNames: ['Abo Yousif'],
  );

  final sampleDay2 = const PrivateLabelDay(
    id: 'u2_2026-10-01',
    organizationUID: 'org1',
    companyUID: 'comp1',
    delegateUid: 'u2',
    delegateName: 'Ahmed Ali',
    date: '2026-10-01',
    month: '2026-10',
    type: PrivateLabelDayType.worked,
    auditsCount: 2,
    rejectedCount: 0,
    branchNames: ['Semouha'],
  );

  setUp(() {
    repo = _MockRepo();
    getOrgMonthDays = GetOrganizationPrivateLabelDays(repo);
    getBranches = GetPrivateLabelBranches(repo);

    when(() => repo.getBranches(any()))
        .thenAnswer((_) async => const Right(['Abo Yousif', 'Semouha']));
    when(() => repo.getOrganizationMonthDays(
          organizationUID: any(named: 'organizationUID'),
          monthKey: any(named: 'monthKey'),
          companyUID: any(named: 'companyUID'),
        )).thenAnswer((_) async => Right([sampleDay1, sampleDay2]));
  });

  PrivateLabelReportBloc buildBloc() {
    return PrivateLabelReportBloc(
      getOrgMonthDays: getOrgMonthDays,
      getBranches: getBranches,
      clock: () => DateTime(2026, 10, 7),
    );
  }

  group('PrivateLabelReportBloc & State Tests', () {
    blocTest<PrivateLabelReportBloc, PrivateLabelReportState>(
      'loads report data, calculates branch scores and marketer KPIs',
      build: () => buildBloc(),
      act: (bloc) => bloc.add(const PrivateLabelReportStarted(
        organizationUID: 'org1',
        companyUID: 'comp1',
      )),
      expect: () => [
        predicate<PrivateLabelReportState>((s) => s.status == PrivateLabelReportStatus.loading),
        predicate<PrivateLabelReportState>((s) {
          return s.status == PrivateLabelReportStatus.ready &&
              s.branchReports.length == 2 &&
              s.marketerReports.length == 2 &&
              s.branchReports.any((b) => b.branchName == 'Abo Yousif' && b.totalAudits == 5) &&
              s.marketerReports.any((m) => m.delegateUid == 'u1' && m.delegateName == 'Sobhy Kassem');
        }),
      ],
    );

    blocTest<PrivateLabelReportBloc, PrivateLabelReportState>(
      'updates view mode and sort mode correctly',
      build: () => buildBloc(),
      act: (bloc) {
        bloc.add(const PrivateLabelReportViewModeChanged(PrivateLabelReportViewMode.marketers));
        bloc.add(const PrivateLabelReportSortModeChanged(PrivateLabelReportSortMode.alphabetical));
      },
      expect: () => [
        predicate<PrivateLabelReportState>(
            (s) => s.viewMode == PrivateLabelReportViewMode.marketers),
        predicate<PrivateLabelReportState>(
            (s) => s.sortMode == PrivateLabelReportSortMode.alphabetical),
      ],
    );

    test('filteredBranchReports sorts descending by achievementScore', () {
      const b1 = BranchReportData(
        branchName: 'Abo Yousif',
        achievementScore: 60.0,
        totalAudits: 10,
        marketerUids: ['u1'],
        marketerNames: ['Sobhy'],
      );
      const b2 = BranchReportData(
        branchName: 'Semouha',
        achievementScore: 90.0,
        totalAudits: 5,
        marketerUids: ['u2'],
        marketerNames: ['Ahmed'],
      );

      final state = const PrivateLabelReportState(
        monthKey: '2026-10',
        branchReports: [b1, b2],
        sortMode: PrivateLabelReportSortMode.highestScore,
      );

      final sorted = state.filteredBranchReports;
      expect(sorted.first.branchName, 'Semouha');
      expect(sorted.last.branchName, 'Abo Yousif');
    });

    test('filteredMarketerReports filters by search query', () {
      const kpi = PrivateLabelKpi(
        year: 2026,
        month: 10,
        daysInMonth: 31,
        elapsedDays: 7,
        achievedDays: 6,
        restDaysUsed: 1,
        restAllowance: 4,
        missedDays: 0,
        todayStatus: PrivateLabelTodayStatus.achieved,
        todayAuditsCount: 1,
      );

      const m1 = MarketerReportData(
        delegateUid: 'u1',
        delegateName: 'Sobhy Kassem',
        kpi: kpi,
        totalAudits: 10,
        branchNames: ['Abo Yousif'],
      );
      const m2 = MarketerReportData(
        delegateUid: 'u2',
        delegateName: 'Ahmed Ali',
        kpi: kpi,
        totalAudits: 5,
        branchNames: ['Semouha'],
      );

      final state = const PrivateLabelReportState(
        monthKey: '2026-10',
        marketerReports: [m1, m2],
        searchQuery: 'Sobhy',
      );

      final filtered = state.filteredMarketerReports;
      expect(filtered.length, 1);
      expect(filtered.first.delegateName, 'Sobhy Kassem');
    });

    test('updates monthKey on PrivateLabelReportMonthChanged', () {
      final bloc = buildBloc();
      bloc.add(const PrivateLabelReportMonthChanged('2026-09'));
      expectLater(
        bloc.stream,
        emitsThrough(predicate<PrivateLabelReportState>((s) => s.monthKey == '2026-09')),
      );
    });
  });
}

