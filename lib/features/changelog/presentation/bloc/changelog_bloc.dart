import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/changelog/domain/usecases/get_new_updates.dart';
import 'package:delegate_app/features/changelog/domain/usecases/get_all_updates.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_event.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_state.dart';

class ChangelogBloc extends Bloc<ChangelogEvent, ChangelogState> {
  final GetNewUpdates getNewUpdates;
  final GetAllUpdates getAllUpdates;

  ChangelogBloc({required this.getNewUpdates, required this.getAllUpdates})
    : super(ChangelogInitial()) {
    on<CheckForNewUpdates>(_onCheckForNewUpdates);
    on<LoadAllUpdates>(_onLoadAllUpdates);
    on<DismissNewUpdates>(_onDismissNewUpdates);
  }

  Future<void> _onCheckForNewUpdates(
    CheckForNewUpdates event,
    Emitter<ChangelogState> emit,
  ) async {
    // Don't show loading for the startup check — it's silent.
    final result = await getNewUpdates(NoParams());

    result.fold(
      // On failure, silently do nothing (don't block the app).
      (_) => emit(ChangelogNoNewUpdates()),
      (updates) {
        if (updates.isEmpty) {
          emit(ChangelogNoNewUpdates());
        } else {
          emit(ChangelogHasNewUpdates(updates));
        }
      },
    );
  }

  Future<void> _onLoadAllUpdates(
    LoadAllUpdates event,
    Emitter<ChangelogState> emit,
  ) async {
    emit(ChangelogLoading());

    final result = await getAllUpdates(NoParams());

    result.fold(
      (failure) => emit(ChangelogError(failure.message)),
      (updates) => emit(ChangelogAllLoaded(updates)),
    );
  }

  void _onDismissNewUpdates(
    DismissNewUpdates event,
    Emitter<ChangelogState> emit,
  ) {
    emit(ChangelogNoNewUpdates());
  }
}
