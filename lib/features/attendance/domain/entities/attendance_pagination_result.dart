import 'package:equatable/equatable.dart';
import 'attendance.dart';

class AttendancePaginationResult extends Equatable {
  final List<Attendance> items;
  final dynamic lastDoc; // This will hold the Firestore DocumentSnapshot
  final bool hasReachedMax;

  const AttendancePaginationResult({
    required this.items,
    this.lastDoc,
    required this.hasReachedMax,
  });

  @override
  List<Object?> get props => [items, lastDoc, hasReachedMax];
}
