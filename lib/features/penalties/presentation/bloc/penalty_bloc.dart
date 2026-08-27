import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/create_penalty_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_all_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_company_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';

class PenaltyBloc extends Bloc<PenaltyEvent, PenaltyState> {
  final CreatePenaltyUseCase createPenaltyUseCase;
  final GetCompanyPenaltiesUseCase getCompanyPenaltiesUseCase;
  final GetAllPenaltiesUseCase getAllPenaltiesUseCase;
  final PenaltyRepository repository;

  PenaltyBloc({
    required this.createPenaltyUseCase,
    required this.getCompanyPenaltiesUseCase,
    required this.getAllPenaltiesUseCase,
    required this.repository,
  }) : super(PenaltyInitialState()) {
    on<LoadCompanyPenaltiesEvent>(_onLoadCompanyPenalties);
    on<LoadAllPenaltiesEvent>(_onLoadAllPenalties);
    on<CreatePenaltyRequestedEvent>(_onCreatePenaltyRequested);
    on<UpdatePenaltyStatusEvent>(_onUpdatePenaltyStatus);
    on<DeletePenaltyEvent>(_onDeletePenalty);
  }

  Future<void> _onLoadCompanyPenalties(
    LoadCompanyPenaltiesEvent event,
    Emitter<PenaltyState> emit,
  ) async {
    emit(PenaltyLoadingState());
    final result = await getCompanyPenaltiesUseCase(event.companyId);

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
