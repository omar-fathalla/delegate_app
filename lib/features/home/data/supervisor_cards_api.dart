// TAS-55: a delegate no longer reads the other delegate documents of its
// company (national ID, phone, document URLs). The supervisor card on the
// home screen gets the supervisors' name, phone, email and photo from the
// getMySupervisorCards callable instead.
import 'package:cloud_functions/cloud_functions.dart';

class SupervisorCard {
  const SupervisorCard({
    required this.uid,
    required this.displayName,
    required this.phoneNumber,
    required this.email,
    required this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String phoneNumber;
  final String email;
  final String photoUrl;

  static String _s(Object? v) => v is String ? v.trim() : '';

  factory SupervisorCard.fromMap(Map<Object?, Object?> m) => SupervisorCard(
        uid: _s(m['uid']),
        displayName: _s(m['displayName']),
        phoneNumber: _s(m['phoneNumber']),
        email: _s(m['email']),
        photoUrl: _s(m['photoUrl']),
      );
}

class SupervisorCardsApi {
  SupervisorCardsApi({
    Future<Object?> Function(Map<String, dynamic> request)? call,
  }) : _call = call ?? _defaultCall;

  final Future<Object?> Function(Map<String, dynamic> request) _call;

  static Future<Object?> _defaultCall(Map<String, dynamic> request) async {
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('getMySupervisorCards')
        .call<Object?>(request);
    return result.data;
  }

  /// Supervisors of [companyUID] in [organizationUID]; empty on any failure
  /// so the card falls back to the company document.
  Future<List<SupervisorCard>> fetch({
    required String organizationUID,
    required String companyUID,
  }) async {
    try {
      final data = await _call({
        'organizationUID': organizationUID,
        'companyUID': companyUID,
      });
      if (data is! Map) return const [];
      final list = data['supervisors'];
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) SupervisorCard.fromMap(item),
      ];
    } catch (_) {
      return const [];
    }
  }
}
