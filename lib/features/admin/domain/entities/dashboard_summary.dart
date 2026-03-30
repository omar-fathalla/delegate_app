import 'package:equatable/equatable.dart';

class DashboardSummary extends Equatable {
  final int totalDelegates;
  final int checkedInToday;
  final int absentToday;

  const DashboardSummary({
    required this.totalDelegates,
    required this.checkedInToday,
    required this.absentToday,
  });

  @override
  List<Object?> get props => [totalDelegates, checkedInToday, absentToday];
}
