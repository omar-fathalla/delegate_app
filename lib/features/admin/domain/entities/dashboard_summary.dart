import 'package:equatable/equatable.dart';

class DashboardSummary extends Equatable {
  final int totalDelegates;
  final int checkedInToday;
  final int absentToday;
  final int totalCompanies;

  const DashboardSummary({
    required this.totalDelegates,
    required this.checkedInToday,
    required this.absentToday,
    this.totalCompanies = 0,
  });

  @override
  List<Object?> get props => [
        totalDelegates,
        checkedInToday,
        absentToday,
        totalCompanies,
      ];
}
