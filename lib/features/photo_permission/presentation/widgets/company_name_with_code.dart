import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CompanyNameWithCode extends StatelessWidget {
  final String organizationUID;
  final String companyUID;
  final String companyName;
  final int? companyCode;
  final TextStyle? style;

  const CompanyNameWithCode({
    super.key,
    required this.organizationUID,
    required this.companyUID,
    required this.companyName,
    this.companyCode,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (companyCode != null && companyCode != 0) {
      return Text(
        '$companyName - كود: $companyCode',
        style: style,
      );
    }

    Future<String?> fetchCompanyCode() async {
      try {
        if (organizationUID.isNotEmpty && companyUID.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('organizations')
              .doc(organizationUID)
              .collection('companies')
              .doc(companyUID)
              .get();
          if (doc.exists) {
            final data = doc.data();
            final code = data?['companyCodeInOrg']?.toString() ??
                data?['companyCode']?.toString() ??
                data?['code']?.toString();
            if (code != null && code.isNotEmpty) return code;
          }
        }
        if (companyUID.isNotEmpty) {
          final query = await FirebaseFirestore.instance
              .collectionGroup('companies')
              .where(FieldPath.documentId, isEqualTo: companyUID)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            final data = query.docs.first.data();
            final code = data['companyCodeInOrg']?.toString() ??
                data['companyCode']?.toString() ??
                data['code']?.toString();
            if (code != null && code.isNotEmpty) return code;
          }
        }
      } catch (_) {}
      return null;
    }

    return FutureBuilder<String?>(
      future: fetchCompanyCode(),
      builder: (context, snapshot) {
        String display = companyName;
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
          display = '$companyName - كود: ${snapshot.data}';
        }
        return Text(
          display,
          style: style,
        );
      },
    );
  }
}
