part of 'branch_bloc.dart';

abstract class BranchState extends Equatable {
  const BranchState();

  @override
  List<Object?> get props => [];
}

class BranchInitial extends BranchState {}

class BranchLoading extends BranchState {}

class BranchLoaded extends BranchState {
  final List<Branch> branches;

  const BranchLoaded({required this.branches});

  @override
  List<Object> get props => [branches];
}

class BranchActionSuccess extends BranchState {
  final Branch branch;

  const BranchActionSuccess({required this.branch});

  @override
  List<Object> get props => [branch];
}

class BranchUpdateSuccess extends BranchState {
  final Branch branch;

  const BranchUpdateSuccess({required this.branch});

  @override
  List<Object> get props => [branch];
}

class BranchDeleteSuccess extends BranchState {
  const BranchDeleteSuccess();
}

class BranchError extends BranchState {
  final String message;

  const BranchError({required this.message});

  @override
  List<Object> get props => [message];
}
