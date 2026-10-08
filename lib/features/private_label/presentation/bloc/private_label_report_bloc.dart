import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_organization_private_label_days.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_branches.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'private_label_report_event.dart';
part 'private_label_report_state.dart';

/// BLoC for Private Label executive and branch/marketer performance reporting.
class PrivateLabelReportBloc
    extends Bloc<PrivateLabelReportEvent, PrivateLabelReportState> {
  final GetOrganizationPrivateLabelDays getOrgMonthDays;
  final GetPrivateLabelBranches getBranches;
  final DateTime Function() clock;

  String _org = '';
  String _company = '';

  PrivateLabelReportBloc({
    required this.getOrgMonthDays,
    required this.getBranches,
    DateTime Function()? clock,
  })  : clock = clock ?? DateTime.now,
        super(PrivateLabelReportState(
          monthKey: PrivateLabelDates.monthKey(
            (clock ?? DateTime.now)().year,
            (clock ?? DateTime.now)().month,
          ),
        )) {
    on<PrivateLabelReportStarted>(_onStarted);
    on<PrivateLabelReportMonthChanged>(_onMonthChanged);
    on<PrivateLabelReportBranchFilterChanged>(_onBranchFilterChanged);
    on<PrivateLabelReportSearchQueryChanged>(_onSearchQueryChanged);
    on<PrivateLabelReportViewModeChanged>(_onViewModeChanged);
    on<PrivateLabelReportSortModeChanged>(_onSortModeChanged);
    on<PrivateLabelReportRefreshRequested>((event, emit) => _loadReport(emit));
  }

  Future<void> _onStarted(
    PrivateLabelReportStarted event,
    Emitter<PrivateLabelReportState> emit,
  ) async {
    _org = event.organizationUID;
    _company = event.companyUID;
    await _loadReport(emit);
  }

  Future<void> _onMonthChanged(
    PrivateLabelReportMonthChanged event,
    Emitter<PrivateLabelReportState> emit,
  ) async {
    if (state.monthKey == event.monthKey) return;
    emit(state.copyWith(monthKey: event.monthKey));
    await _loadReport(emit);
  }

  void _onBranchFilterChanged(
    PrivateLabelReportBranchFilterChanged event,
    Emitter<PrivateLabelReportState> emit,
  ) {
    emit(state.copyWith(
      selectedBranch: event.branch,
      clearSelectedBranch: event.branch == null,
    ));
  }

  void _onSearchQueryChanged(
    PrivateLabelReportSearchQueryChanged event,
    Emitter<PrivateLabelReportState> emit,
  ) {
    emit(state.copyWith(searchQuery: event.query));
  }

  void _onViewModeChanged(
    PrivateLabelReportViewModeChanged event,
    Emitter<PrivateLabelReportState> emit,
  ) {
    emit(state.copyWith(viewMode: event.mode));
  }

  void _onSortModeChanged(
    PrivateLabelReportSortModeChanged event,
    Emitter<PrivateLabelReportState> emit,
  ) {
    emit(state.copyWith(sortMode: event.mode));
  }

  Future<void> _loadReport(Emitter<PrivateLabelReportState> emit) async {
    if (_org.isEmpty) return;
    final currentMonth = state.monthKey;
    emit(state.copyWith(status: PrivateLabelReportStatus.loading));

    final results = await Future.wait([
      getBranches(_org),
      getOrgMonthDays(GetOrganizationPrivateLabelDaysParams(
        organizationUID: _org,
        monthKey: currentMonth,
        companyUID: _company.isNotEmpty ? _company : null,
      )),
    ]);

    if (state.monthKey != currentMonth) return;

    final branchesRes = results[0] as Either<Failure, List<String>>;
    final monthDaysRes = results[1] as Either<Failure, List<PrivateLabelDay>>;

    final branches = branchesRes.fold((_) => state.branches, (b) => b);

    monthDaysRes.fold(
      (failure) => emit(state.copyWith(
        status: PrivateLabelReportStatus.failure,
        errorMessage: failure.message,
      )),
      (days) {
        final parts = currentMonth.split('-');
        final year = int.tryParse(parts.first) ?? clock().year;
        final month = parts.length > 1 ? (int.tryParse(parts[1]) ?? clock().month) : clock().month;
        final today = clock();

        // 1. Group days by marketer
        final daysByDelegate = <String, List<PrivateLabelDay>>{};
        final marketerNames = <String, String>{};
        final marketerBranches = <String, Set<String>>{};
        final marketerAudits = <String, int>{};
        final marketerRejected = <String, int>{};

        for (final d in days) {
          daysByDelegate.putIfAbsent(d.delegateUid, () => []).add(d);
          if (d.delegateName.isNotEmpty) {
            marketerNames[d.delegateUid] = d.delegateName;
          }
          final branchesSet = marketerBranches.putIfAbsent(d.delegateUid, () => <String>{});
          for (final b in d.branchNames) {
            if (b.trim().isNotEmpty) branchesSet.add(b.trim());
          }
          marketerAudits[d.delegateUid] = (marketerAudits[d.delegateUid] ?? 0) + d.auditsCount;
          marketerRejected[d.delegateUid] = (marketerRejected[d.delegateUid] ?? 0) + d.rejectedCount;
        }

        // 2. Build MarketerReportData
        final marketerReports = <MarketerReportData>[];
        final marketerKpis = <String, PrivateLabelKpi>{};

        for (final entry in daysByDelegate.entries) {
          final uid = entry.key;
          final mDays = entry.value;
          final kpi = PrivateLabelKpi.calculate(
            year: year,
            month: month,
            days: mDays,
            restAllowance: 4,
            today: today,
          );
          marketerKpis[uid] = kpi;

          marketerReports.add(MarketerReportData(
            delegateUid: uid,
            delegateName: marketerNames[uid] ?? uid,
            kpi: kpi,
            totalAudits: marketerAudits[uid] ?? 0,
            totalRejected: marketerRejected[uid] ?? 0,
            branchNames: marketerBranches[uid]?.toList() ?? const [],
          ));
        }

        // 3. Build BranchReportData
        final allBranchNames = <String>{...branches};
        for (final d in days) {
          for (final b in d.branchNames) {
            if (b.trim().isNotEmpty) allBranchNames.add(b.trim());
          }
        }

        final branchReports = <BranchReportData>[];

        for (final branch in allBranchNames) {
          final branchMarketerUids = <String>{};
          var branchAudits = 0;
          var branchRejected = 0;

          for (final d in days) {
            if (d.branchNames.any((b) => b.trim() == branch)) {
              branchMarketerUids.add(d.delegateUid);
              branchAudits += d.auditsCount;
              branchRejected += d.rejectedCount;
            }
          }

          final mNames = branchMarketerUids.map((uid) => marketerNames[uid] ?? uid).toList()..sort();

          final scores = branchMarketerUids
              .map((uid) => marketerKpis[uid]?.scorePercentage ?? 0.0)
              .toList();

          final double avgScore;
          if (scores.isEmpty) {
            avgScore = 0.0;
          } else {
            final avg = scores.reduce((a, b) => a + b) / scores.length;
            avgScore = double.parse(avg.toStringAsFixed(1));
          }

          branchReports.add(BranchReportData(
            branchName: branch,
            achievementScore: avgScore,
            totalAudits: branchAudits,
            totalRejected: branchRejected,
            marketerUids: branchMarketerUids.toList(),
            marketerNames: mNames,
          ));
        }

        emit(state.copyWith(
          status: PrivateLabelReportStatus.ready,
          branches: branches,
          branchReports: branchReports,
          marketerReports: marketerReports,
          clearError: true,
        ));
      },
    );
  }
}
