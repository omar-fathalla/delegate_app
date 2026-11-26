import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class CompanyNameWithCode extends StatelessWidget {
  final String organizationUID;
  final String companyUID;
  final String companyName;
  final int? companyCode;
  final TextStyle? style;
  final TextStyle? codeStyle;
  final bool twoLines;

  const CompanyNameWithCode({
    super.key,
    required this.organizationUID,
    required this.companyUID,
    required this.companyName,
    this.companyCode,
    this.style,
    this.codeStyle,
    this.twoLines = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    String codeLabel(String c) => l10n?.codeLabel(c) ?? 'كود: $c';
    final effectiveCodeStyle = codeStyle ??
        TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
        );

    Widget buildTwoLines(String? code) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            companyName,
            style: style ?? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (code != null && code.isNotEmpty && code != '0') ...[
            const SizedBox(height: 2),
            Text(
              codeLabel(code),
              style: effectiveCodeStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      );
    }

    if (companyCode != null && companyCode != 0) {
      if (twoLines) {
        return buildTwoLines(companyCode.toString());
      }
      return Text(
        '$companyName - ${codeLabel(companyCode.toString())}',
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return FutureBuilder<String?>(
      future: fetchCompanyCode(
        firestore: FirebaseFirestore.instance,
        organizationUID: organizationUID,
        companyUID: companyUID,
      ),
      builder: (context, snapshot) {
        final code = snapshot.data;
        if (twoLines) {
          return buildTwoLines(code);
        }
        String display = companyName;
        if (code != null && code.isNotEmpty && code != '0') {
          display = '$companyName - ${codeLabel(code)}';
        }
        return Text(
          display,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}


String? companyCodeFromData(Map<String, dynamic>? data) {
  if (data == null) return null;
  for (final key in const ['companyCodeInOrg', 'companyCode', 'code']) {
    final code = data[key]?.toString();
    if (code != null && code.isNotEmpty && code != '0') return code;
  }
  return null;
}

/// Looks up a company's display code. Uses the nested document path when
/// [organizationUID] is known. Collection-group fallback filters on the
/// stored `uid` field — never `FieldPath.documentId()` with a bare id
/// (that throws IllegalArgumentException: odd number of segments).
@visibleForTesting
Future<String?> fetchCompanyCode({
  required FirebaseFirestore firestore,
  required String organizationUID,
  required String companyUID,
}) async {
  try {
    if (organizationUID.isNotEmpty && companyUID.isNotEmpty) {
      final doc = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .get();
      if (doc.exists) {
        final code = companyCodeFromData(doc.data());
        if (code != null) return code;
      }
    }
    if (companyUID.isNotEmpty) {
      final query = await firestore
          .collectionGroup('companies')
          .where('uid', isEqualTo: companyUID)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return companyCodeFromData(query.docs.first.data());
      }
    }
  } catch (_) {}
  return null;
}
