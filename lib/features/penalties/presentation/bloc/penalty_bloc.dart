import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/create_penalty_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_all_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_company_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_delegate_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/update_penalty_usecase.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';

class PenaltyBloc extends Bloc<PenaltyEvent, PenaltyState> {
  final CreatePenaltyUseCase createPenaltyUseCase;
  final GetCompanyPenaltiesUseCase getCompanyPenaltiesUseCase;
  final GetAllPenaltiesUseCase getAllPenaltiesUseCase;
  final GetDelegatePenaltiesUseCase? getDelegatePenaltiesUseCase;
  final UpdatePenaltyUseCase? updatePenaltyUseCase;
  final PenaltyRepository repository;

  PenaltyBloc({
    required this.createPenaltyUseCase,
    required this.getCompanyPenaltiesUseCase,
    required this.getAllPenaltiesUseCase,
    this.getDelegatePenaltiesUseCase,
    this.updatePenaltyUseCase,
    required this.repository,
  }) : super(PenaltyInitialState()) {
    on<LoadDelegatePenaltiesEvent>(_onLoadDelegatePenalties);
    on<LoadCompanyPenaltiesEvent>(_onLoadCompanyPenalties);
    on<LoadAllPenaltiesEvent>(_onLoadAllPenalties);
    on<LoadOwnPenaltiesEvent>(_onLoadOwnPenalties);
    on<CreatePenaltyRequestedEvent>(_onCreatePenaltyRequested);
    on<UpdatePenaltyRequestedEvent>(_onUpdatePenaltyRequested);
    on<UpdatePenaltyStatusEvent>(_onUpdatePenaltyStatus);
    on<DeletePenaltyEvent>(_onDeletePenalty);
    on<RespondToPenaltyEvent>(_onRespondToPenalty);
  }

  /// TAS-365: messages 8.2 / 8.4 in USER-SCENARIOS/01-delegate-messages.md.
  static String respondSuccessMessage(PenaltyResponseAction action) {
    switch (action) {
      case PenaltyResponseAction.acknowledge:
        return 'تمام، اتسجل إنك اطلعت على الجزاء.';
      case PenaltyResponseAction.dispute:
        return 'اعتراضك اتبعت: الجزاء مش هيتخصم لحد ما الإدارة ترد.';
      case PenaltyResponseAction.upholdDispute:
        return 'اتسجل القرار: الجزاء هيتخصم في مرتب الشهر ده، والمندوب هيوصله إشعار.';
      case PenaltyResponseAction.cancelPenalty:
        return 'اتسجل القرار: الجزاء اتلغى، والمندوب هيوصله إشعار.';
    }
  }

  Future<void> _onRespondToPenalty(
    RespondToPenaltyEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    final (action, decision) = switch (event.action) {
      PenaltyResponseAction.acknowledge => ('acknowledge', null),
      PenaltyResponseAction.dispute => ('dispute', null),
      PenaltyResponseAction.upholdDispute => ('resolve', 'uphold'),
      PenaltyResponseAction.cancelPenalty => ('resolve', 'cancel'),
    };
    final result = await repository.respondToPenalty(
      penaltyId: event.penaltyId,
      action: action,
      reason: event.reason,
      decision: decision,
    );
    result.fold(
      (failure) => emit(PenaltyActionFailedState(failure.message)),
      (_) => emit(PenaltyActionSuccessState(respondSuccessMessage(event.action))),
    );
  }

  Future<void> _onLoadDelegatePenalties(
    LoadDelegatePenaltiesEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    emit(PenaltyLoadingState());
    final result = getDelegatePenaltiesUseCase != null
        ? await getDelegatePenaltiesUseCase!(
            delegateId: event.delegate.uid,
            companyId: event.delegate.companyUID,
            phoneNumber: event.delegate.phoneNumber,
            fullName: event.delegate.fullName,
          )
        : await repository.getDelegatePenalties(
            delegateId: event.delegate.uid,
            companyId: event.delegate.companyUID,
            phoneNumber: event.delegate.phoneNumber,
            fullName: event.delegate.fullName,
          );

    result.fold(
      (failure) => emit(PenaltyErrorState(failure.message)),
      (penalties) {
        double totalFine = 0.0;
        double deductedFine = 0.0;
        for (var p in penalties) {
          if (p.status != PenaltyStatus.cancelled) {
            totalFine += p.fineAmount;
          }
          if (p.status == PenaltyStatus.deducted) {
            deductedFine += p.fineAmount;
          }
        }
        emit(
          PenaltyLoadedState(
            penalties: penalties,
            totalFineAmount: totalFine,
            deductedAmount: deductedFine,
          ),
        );
      },
    );
  }

  Future<void> _onLoadCompanyPenalties(
    LoadCompanyPenaltiesEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    emit(PenaltyLoadingState());
    final result = await getCompanyPenaltiesUseCase(
      event.companyId,
      organizationId: event.organizationId,
    );

    result.fold(
      (failure) => emit(PenaltyErrorState(failure.message)),
      (penalties) {
        double totalFine = 0.0;
        double deductedFine = 0.0;
        for (var p in penalties) {
          if (p.status != PenaltyStatus.cancelled) {
            totalFine += p.fineAmount;
          }
          if (p.status == PenaltyStatus.deducted) {
            deductedFine += p.fineAmount;
          }
        }
        emit(
          PenaltyLoadedState(
            penalties: penalties,
            totalFineAmount: totalFine,
            deductedAmount: deductedFine,
          ),
        );
      },
    );
  }

  Future<void> _onLoadAllPenalties(
    LoadAllPenaltiesEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    emit(PenaltyLoadingState());
    final result = await getAllPenaltiesUseCase();

    result.fold(
      (failure) => emit(PenaltyErrorState(failure.message)),
      (penalties) {
        double totalFine = 0.0;
        double deductedFine = 0.0;
        for (var p in penalties) {
          if (p.status != PenaltyStatus.cancelled) {
            totalFine += p.fineAmount;
          }
          if (p.status == PenaltyStatus.deducted) {
            deductedFine += p.fineAmount;
          }
        }
        emit(
          PenaltyLoadedState(
            penalties: penalties,
            totalFineAmount: totalFine,
            deductedAmount: deductedFine,
          ),
        );
      },
    );
  }

  Future<void> _onLoadOwnPenalties(
    LoadOwnPenaltiesEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    emit(PenaltyLoadingState());
    final result = await repository.getOwnPenalties(
      uid: event.user.uid,
      companyId: event.user.companyUID,
      phoneNumber: event.user.phoneNumber,
    );

    result.fold(
      (failure) => emit(PenaltyErrorState(failure.message)),
      (penalties) {
        double totalFine = 0.0;
        double deductedFine = 0.0;
        for (var p in penalties) {
          if (p.status != PenaltyStatus.cancelled) {
            totalFine += p.fineAmount;
          }
          if (p.status == PenaltyStatus.deducted) {
            deductedFine += p.fineAmount;
          }
        }
        emit(
          PenaltyLoadedState(
            penalties: penalties,
            totalFineAmount: totalFine,
            deductedAmount: deductedFine,
          ),
        );
      },
    );
  }

  Future<void> _onCreatePenaltyRequested(
    CreatePenaltyRequestedEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    emit(PenaltyLoadingState());

    try {
      final List<EvidenceFile> uploadedEvidences = [...event.penalty.evidenceFiles];

      for (var file in event.evidenceFilesToUpload) {
        final uploadRes = await repository.uploadEvidenceFile(
          file: file,
          penaltyId: event.penalty.penaltyId,
          companyId: event.penalty.companyId,
        );
        uploadRes.fold(
          (_) {}, // ignore error or continue
          (ev) => uploadedEvidences.add(ev),
        );
      }

      final penaltyWithFiles = PenaltyEntity(
        penaltyId: event.penalty.penaltyId,
        companyId: event.penalty.companyId,
        companyName: event.penalty.companyName,
        organizationId: event.penalty.organizationId,
        branchId: event.penalty.branchId,
        branchName: event.penalty.branchName,
        createdById: event.penalty.createdById,
        createdByName: event.penalty.createdByName,
        title: event.penalty.title,
        category: event.penalty.category,
        incidentDescription: event.penalty.incidentDescription,
        fineAmount: event.penalty.fineAmount,
        currency: event.penalty.currency,
        status: event.penalty.status,
        evidenceFiles: uploadedEvidences,
        targetDelegateId: event.penalty.targetDelegateId,
        targetDelegateName: event.penalty.targetDelegateName,
        isRepeated: event.penalty.isRepeated,
        createdAt: event.penalty.createdAt,
        updatedAt: event.penalty.updatedAt,
      );

      final result = await createPenaltyUseCase(penaltyWithFiles);

      result.fold(
        (failure) => emit(PenaltyErrorState(failure.message)),
        (_) => emit(const PenaltyActionSuccessState('تم تسجيل الغرامة والمخالفة بنجاح.')),
      );
    } catch (e) {
      emit(PenaltyErrorState('فشل في تسجيل المخالفة: $e'));
    }
  }

  Future<void> _onUpdatePenaltyRequested(
    UpdatePenaltyRequestedEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    emit(PenaltyLoadingState());

    try {
      final List<EvidenceFile> updatedEvidences = [...event.penalty.evidenceFiles];

      for (var file in event.newEvidenceFilesToUpload) {
        final uploadRes = await repository.uploadEvidenceFile(
          file: file,
          penaltyId: event.penalty.penaltyId,
          companyId: event.penalty.companyId,
        );
        uploadRes.fold(
          (_) {},
          (ev) => updatedEvidences.add(ev),
        );
      }

      final penaltyWithFiles = PenaltyEntity(
        penaltyId: event.penalty.penaltyId,
        companyId: event.penalty.companyId,
        companyName: event.penalty.companyName,
        organizationId: event.penalty.organizationId,
        branchId: event.penalty.branchId,
        branchName: event.penalty.branchName,
        createdById: event.penalty.createdById,
        createdByName: event.penalty.createdByName,
        createdByPhone: event.penalty.createdByPhone,
        title: event.penalty.title,
        category: event.penalty.category,
        incidentDescription: event.penalty.incidentDescription,
        fineAmount: event.penalty.fineAmount,
        currency: event.penalty.currency,
        status: event.penalty.status,
        evidenceFiles: updatedEvidences,
        branchesMarketingApprovedBy: event.penalty.branchesMarketingApprovedBy,
        branchesMarketingApprovedAt: event.penalty.branchesMarketingApprovedAt,
        generalManagerApprovedBy: event.penalty.generalManagerApprovedBy,
        generalManagerApprovedAt: event.penalty.generalManagerApprovedAt,
        rejectionReason: event.penalty.rejectionReason,
        targetDelegateId: event.penalty.targetDelegateId,
        targetDelegateName: event.penalty.targetDelegateName,
        isRepeated: event.penalty.isRepeated,
        createdAt: event.penalty.createdAt,
        updatedAt: DateTime.now(),
      );

      final result = updatePenaltyUseCase != null
          ? await updatePenaltyUseCase!(penaltyWithFiles)
          : await repository.updatePenalty(penaltyWithFiles);

      result.fold(
        (failure) => emit(PenaltyErrorState(failure.message)),
        (_) => emit(const PenaltyActionSuccessState('تم حفظ وتعديل بيانات ومستندات المخالفة بنجاح.')),
      );
    } catch (e) {
      emit(PenaltyErrorState('فشل في تعديل المخالفة: $e'));
    }
  }

  Future<void> _onUpdatePenaltyStatus(
    UpdatePenaltyStatusEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    final result = await repository.updatePenaltyStatus(
      penaltyId: event.penaltyId,
      status: event.status,
      rejectionReason: event.rejectionReason,
      reviewerName: event.reviewerName,
    );

    result.fold(
      (failure) => emit(PenaltyErrorState(failure.message)),
      (_) => emit(const PenaltyActionSuccessState('تم تحديث حالة المخالفة بنجاح.')),
    );
  }

  Future<void> _onDeletePenalty(
    DeletePenaltyEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    final result = await repository.deletePenalty(event.penaltyId);

    result.fold(
      (failure) => emit(PenaltyErrorState(failure.message)),
      (_) => emit(const PenaltyActionSuccessState('تم حذف المخالفة بنجاح.')),
    );
  }
}
