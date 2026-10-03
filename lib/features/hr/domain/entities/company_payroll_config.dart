import 'package:equatable/equatable.dart';

/// أنماط احتساب الرواتب ومسيرات العمل
enum PayrollCalculationMode {
  /// احتساب الراتب بناءً على الساعات الفعلية المنجزة (ساعات العمل × أجر الساعة) + الإجازات المدفوعة
  hourlyRate,

  /// راتب شهري أساسي مع خصم الغياب وساعات العجز والتأخير
  monthlyWithDeductions,
}

extension PayrollCalculationModeExt on PayrollCalculationMode {
  String get code {
    switch (this) {
      case PayrollCalculationMode.hourlyRate:
        return 'hourly_rate';
      case PayrollCalculationMode.monthlyWithDeductions:
        return 'monthly_with_deductions';
    }
  }

  String get label {
    switch (this) {
      case PayrollCalculationMode.hourlyRate:
        return 'احتساب ديناميكي بالساعات المنجزة (ساعات العمل × أجر الساعة)';
      case PayrollCalculationMode.monthlyWithDeductions:
        return 'راتب شهري أساسي مع استقطاع الغياب ونقص الساعات';
    }
  }

  String get shortLabel {
    switch (this) {
      case PayrollCalculationMode.hourlyRate:
        return 'بالساعات المنجزة';
      case PayrollCalculationMode.monthlyWithDeductions:
        return 'شهري مع استقطاع';
    }
  }

  static PayrollCalculationMode fromCode(String? code) {
    if (code == 'hourly_rate') return PayrollCalculationMode.hourlyRate;
    return PayrollCalculationMode.monthlyWithDeductions;
  }
}

/// سياسة وإعدادات مسيرات الرواتب وساعات العمل على مستوى الشركة
class CompanyPayrollConfig extends Equatable {
  final String companyUID;
  final PayrollCalculationMode calculationMode;
  final double defaultDailyShiftHours;
  final double defaultMonthlyBaseSalary;
  final int defaultMonthlyWorkingDays;
  final double? defaultHourlyRate;
  final DateTime? updatedAt;
  final String? updatedBy;

  const CompanyPayrollConfig({
    required this.companyUID,
    this.calculationMode = PayrollCalculationMode.monthlyWithDeductions,
    this.defaultDailyShiftHours = 9.0,
    this.defaultMonthlyBaseSalary = 3500.0,
    this.defaultMonthlyWorkingDays = 26,
    this.defaultHourlyRate,
    this.updatedAt,
    this.updatedBy,
  });

  /// أجر الساعة الفعلي المعتمد (إما المحدد يدوياً أو المشتق من الراتب وساعات الشهر)
  double get effectiveHourlyRate {
    if (defaultHourlyRate != null && defaultHourlyRate! > 0) {
      return defaultHourlyRate!;
    }
    final targetHours = defaultMonthlyWorkingDays * defaultDailyShiftHours;
    if (targetHours <= 0) return 0.0;
    return defaultMonthlyBaseSalary / targetHours;
  }

  /// أجر اليوم الفعلي المعتمد
  double get effectiveDailyRate => effectiveHourlyRate * defaultDailyShiftHours;

  CompanyPayrollConfig copyWith({
    String? companyUID,
    PayrollCalculationMode? calculationMode,
    double? defaultDailyShiftHours,
    double? defaultMonthlyBaseSalary,
    int? defaultMonthlyWorkingDays,
    double? defaultHourlyRate,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return CompanyPayrollConfig(
      companyUID: companyUID ?? this.companyUID,
      calculationMode: calculationMode ?? this.calculationMode,
      defaultDailyShiftHours: defaultDailyShiftHours ?? this.defaultDailyShiftHours,
      defaultMonthlyBaseSalary: defaultMonthlyBaseSalary ?? this.defaultMonthlyBaseSalary,
      defaultMonthlyWorkingDays: defaultMonthlyWorkingDays ?? this.defaultMonthlyWorkingDays,
      defaultHourlyRate: defaultHourlyRate ?? this.defaultHourlyRate,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  @override
  List<Object?> get props => [
        companyUID,
        calculationMode,
        defaultDailyShiftHours,
        defaultMonthlyBaseSalary,
        defaultMonthlyWorkingDays,
        defaultHourlyRate,
        updatedAt,
        updatedBy,
      ];
}
