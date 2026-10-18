import 'dart:async';

import 'package:delegate_app/features/private_label/data/datasources/private_label_remote_data_source.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
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
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'private_label_event.dart';
part 'private_label_state.dart';

/// Marketer-side BLoC: KPI, daily documentation, offline queue and rest days.
class PrivateLabelBloc extends Bloc<PrivateLabelEvent, PrivateLabelState> {
  final GetCachedPrivateLabelMonth getCachedMonth;
  final GetPrivateLabelMonth getMonth;
  final SubmitPrivateLabelAudit submitAudit;
  final SyncPendingPrivateLabelAudits syncPendingAudits;
  final GetPendingPrivateLabelAudits getPendingAudits;
  final RegisterPrivateLabelRestDay registerRestDay;
  final CancelPrivateLabelRestDay cancelRestDay;
  final GetPrivateLabelAudits getAudits;
  final GetPrivateLabelProducts getProducts;
  final GetPrivateLabelBranches getBranches;
  final DateTime Function() clock;

  StreamSubscription<bool>? _connectivitySub;
  int _feedbackSeq = 0;

  String _org = '';
  String _company = '';
  String _uid = '';
  String _name = '';

  PrivateLabelBloc({
    required this.getCachedMonth,
    required this.getMonth,
    required this.submitAudit,
    required this.syncPendingAudits,
    required this.getPendingAudits,
    required this.registerRestDay,
    required this.cancelRestDay,
    required this.getAudits,
    required this.getProducts,
    required this.getBranches,
    DateTime Function()? clock,
    Stream<bool>? connectivityStream,
  })  : clock = clock ?? DateTime.now,
        super(PrivateLabelState(
          year: (clock ?? DateTime.now)().year,
          month: (clock ?? DateTime.now)().month,
        )) {
    on<PrivateLabelStarted>(_onStarted);
    on<PrivateLabelRefreshRequested>(_onRefresh);
    on<PrivateLabelMonthChanged>(_onMonthChanged);
    on<PrivateLabelAuditSubmitted>(_onSubmitted);
    on<PrivateLabelRestDayRequested>(_onRestRequested);
    on<PrivateLabelRestDayCancelled>(_onRestCancelled);
    on<PrivateLabelSyncRequested>(_onSyncRequested);
    on<PrivateLabelDateSelected>(_onDateSelected);

    // Auto-sync queued audits the moment the device gets back online.
    _connectivitySub = connectivityStream?.listen((online) {
      if (online && _uid.isNotEmpty && !isClosed) {
        add(const PrivateLabelSyncRequested());
      }
    });
  }

  String get todayKey => PrivateLabelDates.dayKey(clock());

  PrivateLabelFeedback _feedback(String message, PrivateLabelFeedbackType type) =>
      PrivateLabelFeedback(id: ++_feedbackSeq, message: message, type: type);

  // ─────────────────────────── Derivations ───────────────────────────

  /// Merges offline drafts into server days so the KPI reflects them instantly.
  List<PrivateLabelDay> _mergeDays(
    List<PrivateLabelDay> serverDays,
    List<PrivateLabelAuditDraft> pending,
    int year,
    int month,
  ) {
    final monthKey = PrivateLabelDates.monthKey(year, month);
    final byDate = {for (final d in serverDays) d.date: d};
    final pendingByDate = <String, List<PrivateLabelAuditDraft>>{};
    for (final draft in pending) {
      if (draft.auditMonth != monthKey) continue;
      pendingByDate.putIfAbsent(draft.auditDate, () => []).add(draft);
    }
    pendingByDate.forEach((date, drafts) {
      final existing = byDate[date];
      final branches = {
        ...?existing?.branchNames,
        ...drafts.map((d) => d.branchName),
      }.toList();
      if (existing == null) {
        byDate[date] = PrivateLabelDay(
          id: PrivateLabelDates.dayDocId(_uid, date),
          organizationUID: _org,
          companyUID: _company,
          delegateUid: _uid,
          delegateName: _name,
          date: date,
          month: monthKey,
          type: PrivateLabelDayType.worked,
          auditsCount: drafts.length,
          branchNames: branches,
          isLocalOnly: true,
        );
      } else {
        byDate[date] = existing.copyWith(
          type: PrivateLabelDayType.worked,
          auditsCount: existing.isRest ? drafts.length : existing.auditsCount + drafts.length,
          branchNames: branches,
        );
      }
    });
    final merged = byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return merged;
  }

  PrivateLabelState _recompute(PrivateLabelState s) {
    final days = _mergeDays(s.serverDays, s.pendingDrafts, s.year, s.month);
    final kpi = PrivateLabelKpi.calculate(
      year: s.year,
      month: s.month,
      days: days,
      restAllowance: s.restAllowance,
      today: clock(),
    );
    return s.copyWith(days: days, kpi: kpi);
  }

  Future<List<PrivateLabelAuditDraft>> _loadPending() async {
    final result = await getPendingAudits(_uid);
    return result.fold((_) => state.pendingDrafts, (list) => list);
  }

  // ─────────────────────────── Handlers ───────────────────────────

  Future<void> _onStarted(
    PrivateLabelStarted event,
    Emitter<PrivateLabelState> emit,
  ) async {
    _org = event.organizationUID.trim().isNotEmpty
        ? event.organizationUID.trim()
        : 'PiioBFgxaHAeuRdjlDgj';
    _company = event.companyUID;
    _uid = event.delegateUid;
    _name = event.delegateName;

    final now = clock();
    final params = PrivateLabelMonthParams(
      organizationUID: _org,
      delegateUid: _uid,
      year: now.year,
      month: now.month,
    );

    emit(state.copyWith(
      status: PrivateLabelStatus.loading,
      year: now.year,
      month: now.month,
      selectedDate: event.loadDetails ? todayKey : null,
      clearError: true,
    ));

    // 1) Cache-first: render instantly (0 ms) from local storage.
    final pending = await _loadPending();
    final cached = await getCachedMonth(params);
    final cachedData = cached.fold((_) => null, (data) => data);
    if (cachedData != null || pending.isNotEmpty) {
      emit(_recompute(state.copyWith(
        status: PrivateLabelStatus.ready,
        serverDays: cachedData?.days ?? const [],
        restAllowance: cachedData?.restAllowance,
        pendingDrafts: pending,
        isRefreshing: true,
      )));
    } else {
      emit(state.copyWith(pendingDrafts: pending));
    }

    // 2) Revalidate in the background.
    await _revalidateMonth(emit, params);

    if (event.loadDetails) {
      final products = await getProducts(_org);
      final branches = await getBranches(_org);
      emit(state.copyWith(
        products: products.fold((_) => state.products, (p) => p),
        branches: branches.fold((_) => state.branches, (b) => b),
      ));
      await _loadAuditsFor(todayKey, emit);
    }

    if (state.pendingDrafts.isNotEmpty) {
      add(const PrivateLabelSyncRequested());
    }
  }

  Future<void> _revalidateMonth(
    Emitter<PrivateLabelState> emit,
    PrivateLabelMonthParams params,
  ) async {
    final fresh = await getMonth(params);
    fresh.fold(
      (failure) {
        if (state.status == PrivateLabelStatus.ready) {
          emit(state.copyWith(
            isRefreshing: false,
            feedback: _feedback(
              'بنعرض آخر بيانات محفوظة لحد ما النت يرجع.',
              PrivateLabelFeedbackType.info,
            ),
          ));
        } else {
          emit(_recompute(state.copyWith(
            status: PrivateLabelStatus.failure,
            isRefreshing: false,
            errorMessage: failure.message,
          )));
        }
      },
      (data) {
        // Ignore stale responses if the user navigated to another month meanwhile.
        if (data.year != state.year || data.month != state.month) return;
        emit(_recompute(state.copyWith(
          status: PrivateLabelStatus.ready,
          serverDays: data.days,
          restAllowance: data.restAllowance,
          isRefreshing: false,
          clearError: true,
        )));
      },
    );
  }

  Future<void> _loadAuditsFor(String date, Emitter<PrivateLabelState> emit) async {
    emit(state.copyWith(selectedDate: date, isLoadingAudits: true));
    final result = await getAudits(GetPrivateLabelAuditsParams(
      organizationUID: _org,
      date: date,
      delegateUid: _uid,
    ));
    if (state.selectedDate != date) return;
    emit(state.copyWith(
      isLoadingAudits: false,
      selectedDateAudits: result.fold((_) => const [], (list) => list),
    ));
  }

  Future<void> _onRefresh(
    PrivateLabelRefreshRequested event,
    Emitter<PrivateLabelState> emit,
  ) async {
    if (_uid.isEmpty) return;
    emit(state.copyWith(isRefreshing: true));
    final pending = await _loadPending();
    emit(_recompute(state.copyWith(pendingDrafts: pending)));
    await _revalidateMonth(
      emit,
      PrivateLabelMonthParams(
        organizationUID: _org,
        delegateUid: _uid,
        year: state.year,
        month: state.month,
      ),
    );
    final products = await getProducts(_org);
    final branches = await getBranches(_org);
    emit(state.copyWith(
      products: products.fold((_) => state.products, (p) => p),
      branches: branches.fold((_) => state.branches, (b) => b),
    ));
    final date = state.selectedDate;
    if (date != null) await _loadAuditsFor(date, emit);
    if (state.pendingDrafts.isNotEmpty) add(const PrivateLabelSyncRequested());
  }

  Future<void> _onMonthChanged(
    PrivateLabelMonthChanged event,
    Emitter<PrivateLabelState> emit,
  ) async {
    if (_uid.isEmpty) return;
    final params = PrivateLabelMonthParams(
      organizationUID: _org,
      delegateUid: _uid,
      year: event.year,
      month: event.month,
    );
    final cached = await getCachedMonth(params);
    final cachedData = cached.fold((_) => null, (d) => d);
    emit(_recompute(state.copyWith(
      year: event.year,
      month: event.month,
      serverDays: cachedData?.days ?? const [],
      restAllowance: cachedData?.restAllowance,
      isRefreshing: true,
    )));
    await _revalidateMonth(emit, params);
  }

  Future<void> _onSubmitted(
    PrivateLabelAuditSubmitted event,
    Emitter<PrivateLabelState> emit,
  ) async {
    emit(state.copyWith(isSubmitting: true));
    final result = await submitAudit(event.draft);
    final pending = await _loadPending();

    await result.fold(
      (failure) async {
        emit(state.copyWith(
          isSubmitting: false,
          feedback: _feedback(failure.message, PrivateLabelFeedbackType.error),
        ));
      },
      (res) async {
        emit(_recompute(state.copyWith(
          isSubmitting: false,
          pendingDrafts: pending,
          feedback: _feedback(
            res.synced
                ? 'تم رفع التوثيق بنجاح'
                : 'تم التوثيق على الموبايل، وهيترفع أول ما النت يرجع',
            res.synced ? PrivateLabelFeedbackType.success : PrivateLabelFeedbackType.info,
          ),
        )));
        if (res.synced) {
          await _revalidateMonth(
            emit,
            PrivateLabelMonthParams(
              organizationUID: _org,
              delegateUid: _uid,
              year: state.year,
              month: state.month,
            ),
          );
          final date = state.selectedDate;
          if (date != null) await _loadAuditsFor(date, emit);
        }
      },
    );
  }

  Future<void> _onRestRequested(
    PrivateLabelRestDayRequested event,
    Emitter<PrivateLabelState> emit,
  ) async {
    if (event.date.compareTo(todayKey) < 0) {
      emit(state.copyWith(
        feedback: _feedback(
          'الإجازة تتسجل للنهارده أو الأيام الجاية بس.',
          PrivateLabelFeedbackType.error,
        ),
      ));
      return;
    }
    final kpi = state.kpi;
    if (kpi != null && kpi.remainingRestDays <= 0) {
      emit(state.copyWith(
        feedback: _feedback(
          'خلّصت رصيد الإجازات للشهر ده.',
          PrivateLabelFeedbackType.error,
        ),
      ));
      return;
    }

    emit(state.copyWith(isUpdatingRest: true));
    final result = await registerRestDay(RegisterRestDayParams(
      organizationUID: _org,
      companyUID: _company,
      delegateUid: _uid,
      delegateName: _name,
      date: event.date,
      restAllowance: state.restAllowance,
    ));
    result.fold(
      (failure) => emit(state.copyWith(
        isUpdatingRest: false,
        feedback: _feedback(failure.message, PrivateLabelFeedbackType.error),
      )),
      (day) {
        final serverDays = [
          ...state.serverDays.where((d) => d.date != day.date),
          day,
        ];
        emit(_recompute(state.copyWith(
          isUpdatingRest: false,
          serverDays: serverDays,
          feedback: _feedback('تم تسجيل اليوم كإجازة', PrivateLabelFeedbackType.success),
        )));
      },
    );
  }

  Future<void> _onRestCancelled(
    PrivateLabelRestDayCancelled event,
    Emitter<PrivateLabelState> emit,
  ) async {
    emit(state.copyWith(isUpdatingRest: true));
    final result = await cancelRestDay(CancelRestDayParams(
      organizationUID: _org,
      delegateUid: _uid,
      date: event.date,
    ));
    result.fold(
      (failure) => emit(state.copyWith(
        isUpdatingRest: false,
        feedback: _feedback(failure.message, PrivateLabelFeedbackType.error),
      )),
      (_) => emit(_recompute(state.copyWith(
        isUpdatingRest: false,
        serverDays: state.serverDays
            .where((d) => !(d.date == event.date && d.isRest))
            .toList(),
        feedback: _feedback('تم إلغاء الإجازة ورجعت لرصيدك', PrivateLabelFeedbackType.success),
      ))),
    );
  }

  Future<void> _onSyncRequested(
    PrivateLabelSyncRequested event,
    Emitter<PrivateLabelState> emit,
  ) async {
    if (_uid.isEmpty || state.isSyncing) return;
    final pendingBefore = await _loadPending();
    if (pendingBefore.isEmpty) {
      if (event.manual) {
        emit(state.copyWith(
          feedback: _feedback('كل التوثيقات مترفعة بالفعل', PrivateLabelFeedbackType.success),
        ));
      }
      return;
    }

    emit(state.copyWith(isSyncing: true));
    final result = await syncPendingAudits(_uid);
    final pendingAfter = await _loadPending();

    await result.fold(
      (failure) async {
        emit(_recompute(state.copyWith(
          isSyncing: false,
          pendingDrafts: pendingAfter,
          feedback: event.manual
              ? _feedback(failure.message, PrivateLabelFeedbackType.error)
              : null,
        )));
      },
      (count) async {
        emit(_recompute(state.copyWith(
          isSyncing: false,
          pendingDrafts: pendingAfter,
          feedback: count > 0
              ? _feedback('اترفع $count توثيق كان محفوظ على الموبايل', PrivateLabelFeedbackType.success)
              : null,
        )));
        if (count > 0) {
          await _revalidateMonth(
            emit,
            PrivateLabelMonthParams(
              organizationUID: _org,
              delegateUid: _uid,
              year: state.year,
              month: state.month,
            ),
          );
          final date = state.selectedDate;
          if (date != null) await _loadAuditsFor(date, emit);
        }
      },
    );
  }

  Future<void> _onDateSelected(
    PrivateLabelDateSelected event,
    Emitter<PrivateLabelState> emit,
  ) async {
    if (_uid.isEmpty) return;
    await _loadAuditsFor(event.date, emit);
  }

  @override
  Future<void> close() {
    _connectivitySub?.cancel();
    return super.close();
  }
}
