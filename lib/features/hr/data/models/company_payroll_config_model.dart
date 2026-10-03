import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/hr/domain/entities/company_payroll_config.dart';

class CompanyPayrollConfigModel extends CompanyPayrollConfig {
  const CompanyPayrollConfigModel({
    required super.companyUID,
    super.calculationMode = PayrollCalculationMode.monthlyWithDeductions,
    super.defaultDailyShiftHours = 9.0,
    super.defaultMonthlyBaseSalary = 3500.0,
    super.defaultMonthlyWorkingDays = 26,
    super.defaultHourlyRate,
    super.updatedAt,
    super.updatedBy,
  });

  factory CompanyPayrollConfigModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return CompanyPayrollConfigModel.fromMap(data, doc.id);
  }

  factory CompanyPayrollConfigModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime? updated;
    if (map['updatedAt'] != null) {
      if (map['updatedAt'] is Timestamp) {
        updated = (map['updatedAt'] as Timestamp).toDate();
      } else if (map['updatedAt'] is String) {
        updated = DateTime.tryParse(map['updatedAt']);
      }
    }

    return CompanyPayrollConfigModel(
      companyUID: map['companyUID']?.toString() ?? docId,
      calculationMode: PayrollCalculationModeExt.fromCode(map['calculationMode']?.toString()),
      defaultDailyShiftHours: (map['defaultDailyShiftHours'] as num?)?.toDouble() ?? 9.0,
      defaultMonthlyBaseSalary: (map['defaultMonthlyBaseSalary'] as num?)?.toDouble() ?? 3500.0,
      defaultMonthlyWorkingDays: (map['defaultMonthlyWorkingDays'] as num?)?.toInt() ?? 26,
      defaultHourlyRate: (map['defaultHourlyRate'] as num?)?.toDouble(),
      updatedAt: updated,
      updatedBy: map['updatedBy']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'companyUID': companyUID,
      'calculationMode': calculationMode.code,
      'defaultDailyShiftHours': defaultDailyShiftHours,
      'defaultMonthlyBaseSalary': defaultMonthlyBaseSalary,
      'defaultMonthlyWorkingDays': defaultMonthlyWorkingDays,
      'defaultHourlyRate': defaultHourlyRate,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    };
  }
}
