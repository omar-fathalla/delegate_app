import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

abstract class PenaltyState extends Equatable {
  const PenaltyState();

  @override
  List<Object?> get props => [];
}

class PenaltyInitialState extends PenaltyState {}

class PenaltyLoadingState extends PenaltyState {}

class PenaltyLoadedState extends PenaltyState {
  final List<PenaltyEntity> penalties;
  final double totalFineAmount;
  final double deductedAmount;

  const PenaltyLoadedState({
    required this.penalties,
    required this.totalFineAmount,
    required this.deductedAmount,
  });

  @override
  List<Object?> get props => [penalties, totalFineAmount, deductedAmount];
}

class PenaltyActionSuccessState extends PenaltyState {
  final String message;

  const PenaltyActionSuccessState(this.message);

  @override
  List<Object?> get props => [message];
}

class PenaltyErrorState extends PenaltyState {
  final String message;

  const PenaltyErrorState(this.message);

  @override
  List<Object?> get props => [message];
}

/// TAS-365: an action on one penalty failed (e.g. the dispute window
/// closed). The list stays on screen; the page shows the message.
class PenaltyActionFailedState extends PenaltyState {
  final String message;

  const PenaltyActionFailedState(this.message);

  @override
  List<Object?> get props => [message];
}
