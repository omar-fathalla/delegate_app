import 'package:equatable/equatable.dart';

abstract class ChangelogEvent extends Equatable {
  const ChangelogEvent();

  @override
  List<Object?> get props => [];
}

/// Fired on app launch to check for unseen updates.
class CheckForNewUpdates extends ChangelogEvent {}

/// Fired when user opens the full changelog screen.
class LoadAllUpdates extends ChangelogEvent {}

/// Fired when the user dismisses the "What's New" dialog.
class DismissNewUpdates extends ChangelogEvent {}
