import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';

abstract class ChangelogState extends Equatable {
  const ChangelogState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any check.
class ChangelogInitial extends ChangelogState {}

/// Loading state while fetching updates.
class ChangelogLoading extends ChangelogState {}

/// There are new updates the user hasn't seen yet.
class ChangelogHasNewUpdates extends ChangelogState {
  final List<AppUpdate> updates;

  const ChangelogHasNewUpdates(this.updates);

  @override
  List<Object?> get props => [updates];
}

/// No new updates since last check.
class ChangelogNoNewUpdates extends ChangelogState {}

/// All updates loaded (for the full changelog screen).
class ChangelogAllLoaded extends ChangelogState {
  final List<AppUpdate> updates;

  const ChangelogAllLoaded(this.updates);

  @override
  List<Object?> get props => [updates];
}

/// Error state.
class ChangelogError extends ChangelogState {
  final String message;

  const ChangelogError(this.message);

  @override
  List<Object?> get props => [message];
}
