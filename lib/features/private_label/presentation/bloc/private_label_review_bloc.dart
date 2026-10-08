import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/domain/usecases/delete_private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_audits.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_branches.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_products.dart';
import 'package:delegate_app/features/private_label/domain/usecases/review_private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/usecases/save_private_label_product.dart';
import 'package:delegate_app/features/private_label/domain/usecases/update_private_label_audit.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'private_label_review_event.dart';
part 'private_label_review_state.dart';

/// Marketing Promotion (audit) BLoC: daily triage, decisions, catalog, and branch filtering.
class PrivateLabelReviewBloc
    extends Bloc<PrivateLabelReviewEvent, PrivateLabelReviewState> {
  final GetPrivateLabelAudits getAudits;
  final ReviewPrivateLabelAudit reviewAudit;
  final GetPrivateLabelProducts getProducts;
  final SavePrivateLabelProduct saveProduct;
  final DeletePrivateLabelAudit deleteAudit;
  final UpdatePrivateLabelAudit updateAudit;
  final GetPrivateLabelBranches getBranches;
  final DateTime Function() clock;

  String _org = '';
  String _company = '';
  String _reviewerUid = '';
  String _reviewerName = '';
  int _feedbackSeq = 0;

  PrivateLabelReviewBloc({
    required this.getAudits,
    required this.reviewAudit,
    required this.getProducts,
    required this.saveProduct,
    required this.deleteAudit,
    required this.updateAudit,
    required this.getBranches,
    DateTime Function()? clock,
  })  : clock = clock ?? DateTime.now,
        super(const PrivateLabelReviewState()) {
    on<PrivateLabelReviewStarted>(_onStarted);
    on<PrivateLabelReviewDateChanged>(_onDateChanged);
    on<PrivateLabelReviewFilterChanged>(
      (event, emit) => emit(state.copyWith(filter: event.filter)),
    );
    on<PrivateLabelReviewRefreshRequested>((event, emit) => _loadAudits(emit));
    on<PrivateLabelReviewDecisionSubmitted>(_onDecision);
    on<PrivateLabelReviewProductSaved>(_onProductSaved);
    on<PrivateLabelReviewAuditDeleted>(_onAuditDeleted);
    on<PrivateLabelReviewAuditUpdated>(_onAuditUpdated);
    on<PrivateLabelReviewBranchSelected>(_onBranchSelected);
  }

  PrivateLabelReviewFeedback _feedback(String message, {bool isError = false}) =>
      PrivateLabelReviewFeedback(id: ++_feedbackSeq, message: message, isError: isError);

  Future<void> _onStarted(
    PrivateLabelReviewStarted event,
    Emitter<PrivateLabelReviewState> emit,
  ) async {
    _org = event.organizationUID;
    _company = event.companyUID;
    _reviewerUid = event.reviewerUid;
    _reviewerName = event.reviewerName;
    await _loadAudits(emit);
    final products = await getProducts(_org);
    emit(state.copyWith(products: products.fold((_) => state.products, (p) => p)));
  }

  Future<void> _onDateChanged(
    PrivateLabelReviewDateChanged event,
    Emitter<PrivateLabelReviewState> emit,
  ) async {
    emit(state.copyWith(
      date: event.date,
      clearDate: event.date == null,
    ));
    await _loadAudits(emit);
  }

  void _onBranchSelected(
    PrivateLabelReviewBranchSelected event,
    Emitter<PrivateLabelReviewState> emit,
  ) {
    emit(state.copyWith(
      selectedBranch: event.branch,
      clearSelectedBranch: event.branch == null,
    ));
  }

  Future<void> _loadAudits(Emitter<PrivateLabelReviewState> emit) async {
    if (_org.isEmpty) return;
    final date = state.date;
    emit(state.copyWith(status: PrivateLabelReviewStatusView.loading));

    final results = await Future.wait([
      getAudits(GetPrivateLabelAuditsParams(
        organizationUID: _org,
        date: date,
        companyUID: _company,
      )),
      getBranches(_org),
    ]);

    if (state.date != date) return; // Stale response.

    final auditsRes = results[0] as Either<Failure, List<PrivateLabelAudit>>;
    final branchesRes = results[1] as Either<Failure, List<String>>;

    final branches = branchesRes.fold((_) => state.branches, (b) => b);

    auditsRes.fold(
      (failure) => emit(state.copyWith(
        status: PrivateLabelReviewStatusView.failure,
        errorMessage: failure.message,
      )),
      (audits) {
        emit(state.copyWith(
          status: PrivateLabelReviewStatusView.ready,
          audits: audits,
          branches: branches,
          clearError: true,
        ));
      },
    );
  }

  Future<void> _onDecision(
    PrivateLabelReviewDecisionSubmitted event,
    Emitter<PrivateLabelReviewState> emit,
  ) async {
    emit(state.copyWith(savingAuditId: event.auditId));
    final result = await reviewAudit(ReviewAuditParams(
      organizationUID: _org,
      auditId: event.auditId,
      status: event.status,
      reviewerUid: _reviewerUid,
      reviewerName: _reviewerName,
      notes: event.notes,
    ));
    result.fold(
      (failure) => emit(state.copyWith(
        clearSaving: true,
        feedback: _feedback(failure.message, isError: true),
      )),
      (updated) => emit(state.copyWith(
        clearSaving: true,
        audits: state.audits.map((a) => a.id == updated.id ? updated : a).toList(),
        feedback: _feedback(_decisionMessage(event.status)),
      )),
    );
  }

  String _decisionMessage(PrivateLabelReviewStatus status) {
    switch (status) {
      case PrivateLabelReviewStatus.approved:
        return 'تم اعتماد التوثيق';
      case PrivateLabelReviewStatus.priceIssue:
        return 'تم تسجيل مخالفة سعر على الفرع';
      case PrivateLabelReviewStatus.rejected:
        return 'تم رفض التوثيق وإبلاغ السبب';
      case PrivateLabelReviewStatus.pending:
        return 'رجع التوثيق لقائمة الانتظار';
    }
  }

  Future<void> _onProductSaved(
    PrivateLabelReviewProductSaved event,
    Emitter<PrivateLabelReviewState> emit,
  ) async {
    emit(state.copyWith(isSavingProduct: true));
    final result = await saveProduct(event.product);
    result.fold(
      (failure) => emit(state.copyWith(
        isSavingProduct: false,
        feedback: _feedback(failure.message, isError: true),
      )),
      (saved) {
        final products = [
          ...state.products.where((p) => p.id != saved.id),
          saved,
        ]..sort((a, b) => a.name.compareTo(b.name));
        emit(state.copyWith(
          isSavingProduct: false,
          products: products,
          feedback: _feedback('تم حفظ المنتج في الكتالوج'),
        ));
      },
    );
  }

  Future<void> _onAuditDeleted(
    PrivateLabelReviewAuditDeleted event,
    Emitter<PrivateLabelReviewState> emit,
  ) async {
    final audit = event.audit;
    final org = audit.organizationUID.isNotEmpty ? audit.organizationUID : _org;
    emit(state.copyWith(savingAuditId: audit.id));
    final result = await deleteAudit(DeleteAuditParams(
      organizationUID: org,
      auditId: audit.id,
      delegateUid: audit.delegateUid,
      date: audit.auditDate,
    ));
    result.fold(
      (failure) => emit(state.copyWith(
        clearSaving: true,
        feedback: _feedback(failure.message, isError: true),
      )),
      (_) {
        final updatedList = state.audits.where((a) => a.id != audit.id).toList();
        emit(state.copyWith(
          clearSaving: true,
          audits: updatedList,
          feedback: _feedback('تم حذف التوثيق بنجاح'),
        ));
      },
    );
  }

  Future<void> _onAuditUpdated(
    PrivateLabelReviewAuditUpdated event,
    Emitter<PrivateLabelReviewState> emit,
  ) async {
    final audit = event.audit;
    final org = audit.organizationUID.isNotEmpty ? audit.organizationUID : _org;
    emit(state.copyWith(savingAuditId: audit.id));
    final result = await updateAudit(UpdateAuditParams(
      organizationUID: org,
      auditId: audit.id,
      productName: audit.productName,
      productId: audit.productId,
      referencePrice: audit.referencePrice,
      shelfPrice: audit.shelfPrice,
      stockStatus: audit.stockStatus,
      barcode: audit.barcode,
      notes: audit.notes,
    ));
    result.fold(
      (failure) => emit(state.copyWith(
        clearSaving: true,
        feedback: _feedback(failure.message, isError: true),
      )),
      (updated) {
        final updatedList =
            state.audits.map((a) => a.id == updated.id ? updated : a).toList();
        emit(state.copyWith(
          clearSaving: true,
          audits: updatedList,
          feedback: _feedback('تم تعديل بيانات التوثيق بنجاح'),
        ));
      },
    );
  }
}
