import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

// --- States ---
class PaginationState<T> extends Equatable {
  final List<T> items;
  final bool hasReachedMax;
  final bool isLoading;
  final String? errorMessage;
  final dynamic lastDoc; // Firestore DocumentSnapshot

  const PaginationState({
    this.items = const [],
    this.hasReachedMax = false,
    this.isLoading = false,
    this.errorMessage,
    this.lastDoc,
  });

  @override
  List<Object?> get props => [items, hasReachedMax, isLoading, errorMessage, lastDoc];

  PaginationState<T> copyWith({
    List<T>? items,
    bool? hasReachedMax,
    bool? isLoading,
    String? errorMessage,
    dynamic lastDoc,
  }) {
    return PaginationState<T>(
      items: items ?? this.items,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      lastDoc: lastDoc ?? this.lastDoc,
    );
  }
}

// --- Events ---
abstract class PaginationEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadFirstBatchRequested extends PaginationEvent {}
class LoadNextBatchRequested extends PaginationEvent {}

// --- Bloc Implementation ---
class ExamplePaginationBloc extends Bloc<PaginationEvent, PaginationState<dynamic>> {
  final ExampleRepository _repository;
  static const int _pageSize = 20;

  ExamplePaginationBloc(this._repository) : super(const PaginationState()) {
    on<LoadFirstBatchRequested>(_onLoadFirstBatch);
    on<LoadNextBatchRequested>(_onLoadNextBatch);
  }

  Future<void> _onLoadFirstBatch(
    LoadFirstBatchRequested event,
    Emitter<PaginationState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, items: []));
    
    final result = await _repository.fetchItems(limit: _pageSize);
    
    result.fold(
      (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
      (data) => emit(state.copyWith(
        isLoading: false,
        items: data.items,
        lastDoc: data.lastDoc,
        hasReachedMax: data.items.length < _pageSize,
      )),
    );
  }

  Future<void> _onLoadNextBatch(
    LoadNextBatchRequested event,
    Emitter<PaginationState> emit,
  ) async {
    if (state.hasReachedMax || state.isLoading) return;

    final result = await _repository.fetchItems(
      limit: _pageSize,
      startAfter: state.lastDoc,
    );

    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (data) => emit(state.copyWith(
        items: [...state.items, ...data.items],
        lastDoc: data.lastDoc,
        hasReachedMax: data.items.length < _pageSize,
      )),
    );
  }
}

// Mock Repository for reference
abstract class ExampleRepository {
  Future<dynamic> fetchItems({int limit, dynamic startAfter});
}
