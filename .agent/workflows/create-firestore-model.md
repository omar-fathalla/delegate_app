---
description: Create a Firestore-compatible Dart model that strictly matches the existing Angular/TypeScript schema with camelCase keys.
---

# Create a Firestore Model

**CRITICAL:** All JSON keys must use **camelCase** matching the existing Web Dashboard schema exactly. Do NOT invent new field names.

## 1. Check the existing schema

Before creating ANY model, verify the field names in:
- The existing TypeScript/Angular models (in `tashil_reference/` if available).
- The `firestore.rules` file.
- The Firestore console (document structure).

## 2. Create the Domain Entity

Create `lib/features/<feature>/domain/entities/<entity>.dart`:

```dart
import 'package:equatable/equatable.dart';

class DelegatePerson extends Equatable {
  final String uid;
  final String firstName;
  final String middleName;
  final String lastName;
  final String fullName;
  final String nationalityID;  // Note: Capital 'ID'
  final String motherName;
  final String city;
  final String phoneNumber;
  final String gender;         // 'Male' | 'Female'
  final String position;       // 'Supervisor' | 'Promoter'
  final DateTime birthDate;
  final String organizationUID;
  final String companyUID;
  final String status;         // 'Pending' | 'Approved' | 'Suspended' | 'Rejected'

  const DelegatePerson({...});

  @override
  List<Object?> get props => [...];
}
```

## 3. Create the Data Model

Create `lib/features/<feature>/data/models/<entity>_model.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class DelegateModel extends DelegatePerson {
  const DelegateModel({...}) : super(...);

  factory DelegateModel.fromJson(Map<String, dynamic> json) {
    return DelegateModel(
      uid: json['uid'] as String,
      firstName: json['firstName'] as String,
      nationalityID: json['nationalityID'] as String,  // Capital 'ID'
      birthDate: (json['birthDate'] as Timestamp).toDate(),
      organizationUID: json['organizationUID'] as String,
      companyUID: json['companyUID'] as String,
      // ... all other fields
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'firstName': firstName,
      'nationalityID': nationalityID,  // Capital 'ID'
      'birthDate': Timestamp.fromDate(birthDate),
      'organizationUID': organizationUID,
      'companyUID': companyUID,
      // ... all other fields
    };
  }

  factory DelegateModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DelegateModel.fromJson(data);
  }
}
```

## 4. Documents Array model (if applicable)

For entities with a `documents` array field:

```dart
class DelegateDocument {
  final String documentKey;     // One of: 'personalPhoto', 'nationalityId', 
                                 // 'authorizationLetter', 'insuranceLetter',
                                 // 'healthCertificate', 'paymentReceipt'
  final String documentStatus;
  final String documentURL;
  final String? rejectionReason;

  DelegateDocument.fromJson(Map<String, dynamic> json) : ...;
  Map<String, dynamic> toJson() => {...};
}
```

## 5. Firestore Path Rules

**ALWAYS** construct full nested paths:

```dart
// ✅ CORRECT
firestore
  .collection('organizations').doc(orgId)
  .collection('companies').doc(compId)
  .collection('delegates').doc(uid);

// ❌ WRONG — Never access root-level
firestore.collection('delegates').doc(uid);
```

## 6. Timestamp Handling

- **Reading:** Convert `Timestamp` → `DateTime` via `(json['field'] as Timestamp).toDate()`
- **Writing:** Convert `DateTime` → `Timestamp` via `Timestamp.fromDate(dateTime)`
- **Server Time:** For `createdAt`/`updatedAt`/check-in times, use `FieldValue.serverTimestamp()` — NEVER `DateTime.now()`.

## 7. Verify

// turbo
```
flutter analyze
```
