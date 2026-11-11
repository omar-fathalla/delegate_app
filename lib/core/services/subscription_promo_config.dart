import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:flutter/foundation.dart';

/// Loads `config/subscriptions.freePromotionLastDay` into [SubscriptionCycleHelper].
/// Functions remain authoritative for quotes and suspension; the app only mirrors
/// the same document the clients may already read.
class SubscriptionPromoConfig {
  SubscriptionPromoConfig({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  Future<void> refresh() async {
    try {
      FirebaseFirestore? db = _firestore;
      if (db == null) {
        try {
          db = FirebaseFirestore.instance;
        } catch (_) {
          return;
        }
      }
      final snap = await db.doc('config/subscriptions').get();
      final data = snap.data();
      SubscriptionCycleHelper.applyConfig(
        freePromotionLastDay: data?['freePromotionLastDay']?.toString(),
      );
    } catch (e) {
      debugPrint('[SubscriptionPromoConfig] refresh fallback: $e');
      SubscriptionCycleHelper.applyConfig();
    }
  }
}
