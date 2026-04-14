import 'features/admin/data/models/company_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  final data1 = {'companyCodeInOrg': 4818, 'code': '4818'};
  try {
    // We simulate what it does
    final companyCodeInOrg1 = data1['companyCodeInOrg'] ?? '';
    print("Assigning int to String? ${companyCodeInOrg1.runtimeType}");
    String s = companyCodeInOrg1 as String; // This fails!
  } catch (e) {
    print("Error 1: \$e");
  }

  final data2 = {'code': '123'};
  try {
    final code = data2['code'] as int?; // This fails!
  } catch (e) {
    print("Error 2: \$e");
  }
}
