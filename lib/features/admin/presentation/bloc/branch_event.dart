part of 'branch_bloc.dart';

abstract class BranchEvent extends Equatable {
  const BranchEvent();

  @override
  List<Object?> get props => [];
}

class BranchLoadRequested extends BranchEvent {
  const BranchLoadRequested();
}

class BranchAddRequested extends BranchEvent {
  final Branch branch;

  const BranchAddRequested({required this.branch});

  @override
  List<Object> get props => [branch];
}

class BranchDeleteRequested extends BranchEvent {
  final String branchId;

  const BranchDeleteRequested({required this.branchId});

  @override
  List<Object> get props => [branchId];
}
