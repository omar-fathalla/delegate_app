import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_branches.dart';
import 'package:delegate_app/features/admin/domain/usecases/add_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_branch.dart';

part 'branch_event.dart';
part 'branch_state.dart';

class BranchBloc extends Bloc<BranchEvent, BranchState> {
  final GetBranches getBranches;
  final AddBranch addBranch;
  final UpdateBranch updateBranch;
  final DeleteBranch deleteBranch;

  BranchBloc({
    required this.getBranches,
    required this.addBranch,
    required this.updateBranch,
    required this.deleteBranch,
  }) : super(BranchInitial()) {
    on<BranchLoadRequested>(_onLoad);
    on<BranchAddRequested>(_onAdd);
    on<BranchUpdateRequested>(_onUpdate);
    on<BranchDeleteRequested>(_onDelete);
  }

  Future<void> _onLoad(
    BranchLoadRequested event,
    Emitter<BranchState> emit,
  ) async {
    emit(BranchLoading());
    final result = await getBranches(NoParams());
    result.fold(
      (failure) => emit(BranchError(message: failure.message)),
      (branches) => emit(BranchLoaded(branches: branches)),
    );
  }

  Future<void> _onAdd(
    BranchAddRequested event,
    Emitter<BranchState> emit,
  ) async {
    emit(BranchLoading());
    final result = await addBranch(AddBranchParams(branch: event.branch));
    result.fold(
      (failure) => emit(BranchError(message: failure.message)),
      (branch) => emit(BranchActionSuccess(branch: branch)),
    );
  }

  Future<void> _onUpdate(
    BranchUpdateRequested event,
    Emitter<BranchState> emit,
  ) async {
    emit(BranchLoading());
    final result = await updateBranch(UpdateBranchParams(branch: event.branch));
    result.fold(
      (failure) => emit(BranchError(message: failure.message)),
      (branch) => emit(BranchUpdateSuccess(branch: branch)),
    );
  }

  Future<void> _onDelete(
    BranchDeleteRequested event,
    Emitter<BranchState> emit,
  ) async {
    emit(BranchLoading());
    final result = await deleteBranch(
      DeleteBranchParams(branchId: event.branchId),
    );
    result.fold(
      (failure) => emit(BranchError(message: failure.message)),
      (_) => emit(const BranchDeleteSuccess()),
    );
  }
}
