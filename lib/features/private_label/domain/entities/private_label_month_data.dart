import 'package:equatable/equatable.dart';

import 'private_label_day.dart';

/// Raw month data for a marketer: day summaries + the monthly rest allowance.
class PrivateLabelMonthData extends Equatable {
  final int year;
  final int month;
  final List<PrivateLabelDay> days;
  final int restAllowance;

  const PrivateLabelMonthData({
    required this.year,
    required this.month,
    required this.days,
    required this.restAllowance,
  });

  @override
  List<Object?> get props => [year, month, days, restAllowance];
}
