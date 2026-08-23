import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

abstract class PenaltyEvent extends Equatable {
  const PenaltyEvent();

  @override
  List<Object?> get props => [];
}

class LoadCompanyPenaltiesEvent extends PenaltyEvent {
  final String companyId;

  const LoadCompanyPenaltiesEvent(this.companyId);

  @override
  List<Object?> get props => [companyId];
}

class LoadAllPenaltiesEvent extends PenaltyEvent {
  const LoadAllPenaltiesEvent();
}

class CreatePenaltyRequestedEvent extends PenaltyEvent {
  final PenaltyEntity penalty;
  final List<File> evidenceFilesToUpload;

  const CreatePenaltyRequestedEvent({
    required this.penalty,
    this.evidenceFilesToUpload = const [],
  });

  @override
  List<Object?> get props => [penalty, evidenceFilesToUpload];
}

class UpdatePenaltyStatusEvent extends PenaltyEvent {
  final String penaltyId;
  final PenaltyStatus status;

  const UpdatePenaltyStatusEvent({
    required this.penaltyId,
    required this.status,
  });

  @override
  List<Object?> get props => [penaltyId, status];
}

class DeletePenaltyEvent extends PenaltyEvent {
  final String penaltyId;

  const DeletePenaltyEvent(this.penaltyId);

  @override
  List<Object?> get props => [penaltyId];
}
