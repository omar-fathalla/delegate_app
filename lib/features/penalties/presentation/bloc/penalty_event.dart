import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

abstract class PenaltyEvent extends Equatable {
  const PenaltyEvent();

  @override
  List<Object?> get props => [];
}

class LoadDelegatePenaltiesEvent extends PenaltyEvent {
  final Delegate delegate;

  const LoadDelegatePenaltiesEvent(this.delegate);

  @override
  List<Object?> get props => [
        delegate.uid,
        delegate.companyUID,
        delegate.phoneNumber,
        delegate.fullName,
      ];
}

class LoadCompanyPenaltiesEvent extends PenaltyEvent {
  final String companyId;
  final String? organizationId;

  const LoadCompanyPenaltiesEvent(this.companyId, {this.organizationId});

  @override
  List<Object?> get props => [companyId, organizationId];
}

class LoadAllPenaltiesEvent extends PenaltyEvent {
  const LoadAllPenaltiesEvent();
}

/// Penalties issued to [user] (a staff member such as HR), never anyone else's.
class LoadOwnPenaltiesEvent extends PenaltyEvent {
  final Delegate user;

  const LoadOwnPenaltiesEvent(this.user);

  @override
  List<Object?> get props => [user.uid, user.companyUID, user.phoneNumber];
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
  final String? rejectionReason;
  final String? reviewerName;

  const UpdatePenaltyStatusEvent({
    required this.penaltyId,
    required this.status,
    this.rejectionReason,
    this.reviewerName,
  });

  @override
  List<Object?> get props => [penaltyId, status, rejectionReason, reviewerName];
}

class DeletePenaltyEvent extends PenaltyEvent {
  final String penaltyId;

  const DeletePenaltyEvent(this.penaltyId);

  @override
  List<Object?> get props => [penaltyId];
}

class UpdatePenaltyRequestedEvent extends PenaltyEvent {
  final PenaltyEntity penalty;
  final List<File> newEvidenceFilesToUpload;

  const UpdatePenaltyRequestedEvent({
    required this.penalty,
    this.newEvidenceFilesToUpload = const [],
  });

  @override
  List<Object?> get props => [penalty, newEvidenceFilesToUpload];
}


/// TAS-365: what a respondToPenalty call does.
enum PenaltyResponseAction { acknowledge, dispute, upholdDispute, cancelPenalty }

/// TAS-365: the delegate acknowledges / disputes its penalty, or a super
/// admin / chain admin decides a dispute.
class RespondToPenaltyEvent extends PenaltyEvent {
  final String penaltyId;
  final PenaltyResponseAction action;
  final String? reason;

  const RespondToPenaltyEvent({
    required this.penaltyId,
    required this.action,
    this.reason,
  });

  @override
  List<Object?> get props => [penaltyId, action, reason];
}
