import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

class PenaltyCreatorHelper {
  // In-memory cache of resolved phones to prevent redundant Firestore lookups
  static final Map<String, String> _phoneCache = {};

  static String _cleanPhoneNumber(String phone) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

    String cleaned = phone.trim();
    for (int i = 0; i < arabic.length; i++) {
      cleaned = cleaned.replaceAll(arabic[i], english[i]);
    }
    cleaned = cleaned.replaceAll(RegExp(r'[^\d+]'), '');
    return cleaned;
  }

  static String? _extractPhoneFromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final candidate = data['phoneNumber'] ??
        data['phone'] ??
        data['mobile'] ??
        data['tel'] ??
        data['phone_number'];
    if (candidate != null && candidate.toString().trim().isNotEmpty) {
      final cleaned = _cleanPhoneNumber(candidate.toString());
      if (cleaned.isNotEmpty) return cleaned;
    }
    return null;
  }

  /// Resolves the phone number of the creator using multiple fallback strategies
  static Future<String?> resolveCreatorPhone(PenaltyEntity penalty) async {
    final cacheKey = '${penalty.createdById}_${penalty.createdByName}';
    if (_phoneCache.containsKey(cacheKey) && _phoneCache[cacheKey]!.isNotEmpty) {
      return _phoneCache[cacheKey];
    }

    // 1. Direct penalty field
    if (penalty.createdByPhone != null && penalty.createdByPhone!.trim().isNotEmpty) {
      final cleaned = _cleanPhoneNumber(penalty.createdByPhone!);
      if (cleaned.isNotEmpty) {
        _phoneCache[cacheKey] = cleaned;
        return cleaned;
      }
    }

    final firestore = FirebaseFirestore.instance;

    // 2. Look in users/{penalty.createdById}
    if (penalty.createdById.trim().isNotEmpty) {
      try {
        final doc = await firestore.collection('users').doc(penalty.createdById.trim()).get();
        if (doc.exists) {
          final phone = _extractPhoneFromMap(doc.data());
          if (phone != null) {
            _phoneCache[cacheKey] = phone;
            return phone;
          }
        }
      } catch (_) {}

      // 3. Query users where uid == penalty.createdById
      try {
        final q = await firestore
            .collection('users')
            .where('uid', isEqualTo: penalty.createdById.trim())
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final phone = _extractPhoneFromMap(q.docs.first.data());
          if (phone != null) {
            _phoneCache[cacheKey] = phone;
            return phone;
          }
        }
      } catch (_) {}

      // 4. Query collectionGroup('delegates') by document ID or uid
      try {
        final q = await firestore
            .collectionGroup('delegates')
            .where(FieldPath.documentId, isEqualTo: penalty.createdById.trim())
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final phone = _extractPhoneFromMap(q.docs.first.data());
          if (phone != null) {
            _phoneCache[cacheKey] = phone;
            return phone;
          }
        }
      } catch (_) {}

      try {
        final q = await firestore
            .collectionGroup('delegates')
            .where('uid', isEqualTo: penalty.createdById.trim())
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final phone = _extractPhoneFromMap(q.docs.first.data());
          if (phone != null) {
            _phoneCache[cacheKey] = phone;
            return phone;
          }
        }
      } catch (_) {}
    }

    // 5. Query users by displayName / fullName / name
    if (penalty.createdByName.trim().isNotEmpty) {
      final name = penalty.createdByName.trim();
      try {
        for (final field in ['displayName', 'fullName', 'name']) {
          final q = await firestore
              .collection('users')
              .where(field, isEqualTo: name)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final phone = _extractPhoneFromMap(q.docs.first.data());
            if (phone != null) {
              _phoneCache[cacheKey] = phone;
              return phone;
            }
          }
        }
      } catch (_) {}

      // 6. Query collectionGroup('delegates') by fullName / name
      try {
        for (final field in ['fullName', 'name', 'firstName']) {
          final q = await firestore
              .collectionGroup('delegates')
              .where(field, isEqualTo: name)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final phone = _extractPhoneFromMap(q.docs.first.data());
            if (phone != null) {
              _phoneCache[cacheKey] = phone;
              return phone;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Triggers a phone call to the penalty creator
  static Future<void> callCreator(BuildContext context, PenaltyEntity penalty) async {
    final phone = await resolveCreatorPhone(penalty);

    if (phone != null && phone.isNotEmpty) {
      final uri = Uri(scheme: 'tel', path: phone);
      bool launched = false;
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}

      if (!launched) {
        try {
          launched = await launchUrl(uri);
        } catch (_) {}
      }

      if (launched) return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لم يتم العثور على رقم هاتف متاح لمحرر المخالفة (${penalty.createdByName})',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }
}
