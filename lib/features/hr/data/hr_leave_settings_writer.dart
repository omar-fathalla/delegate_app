import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// TAS-74: saves a delegate's annual-leave settings from the HR screens.
///
/// The company delegate doc (`organizations/{org}/companies/{co}/delegates`)
/// is the record and must succeed. The `users/{uid}` copy is best effort:
/// the rules let HR touch a users doc only when it already carries the HR
/// company's `companyUID`, and old delegate users docs often don't. A denied
/// mirror must not turn a saved change into an error for HR.
///
/// Returns whether the users copy was written.
Future<bool> saveDelegateLeaveSettings({
  required FirebaseFirestore firestore,
  required String organizationUID,
  required String companyUID,
  required String delegateUid,
  required Map<String, Object?> payload,
}) async {
  if (organizationUID.isNotEmpty && companyUID.isNotEmpty) {
    await firestore
        .collection('organizations')
        .doc(organizationUID)
        .collection('companies')
        .doc(companyUID)
        .collection('delegates')
        .doc(delegateUid)
        // update(): never create a stub doc.
        .update(payload);
  }
  try {
    final userRef = firestore.collection('users').doc(delegateUid);
    final userDoc = await userRef.get();
    if (!userDoc.exists) return false;
    await userRef.set(payload, SetOptions(merge: true));
    return true;
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    debugPrint('users leave mirror skipped for $delegateUid: ${e.code}');
    return false;
  }
}
