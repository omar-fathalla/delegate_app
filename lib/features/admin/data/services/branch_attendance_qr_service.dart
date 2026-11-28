import 'package:cloud_functions/cloud_functions.dart';

/// The signed attendance QR of a branch (TAS-372), from `branchAttendanceQr`.
class BranchAttendanceQr {
  const BranchAttendanceQr({required this.version, this.payload});

  /// 0 when the branch has no signed QR yet.
  final int version;

  /// The JSON map to encode in the printed QR; null when [version] is 0.
  final Map<String, dynamic>? payload;

  bool get isSigned => version > 0 && payload != null;

  factory BranchAttendanceQr.fromCallable(Object? data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    final v = map['qrVersion'];
    final qr = map['qr'];
    return BranchAttendanceQr(
      version: v is int ? v : 0,
      payload: qr is Map ? Map<String, dynamic>.from(qr) : null,
    );
  }
}

/// Reads or regenerates (version + 1) the signed QR of a branch. Only
/// super-admin, technical support and the chain's org admin may call it
/// (checked on the server).
abstract class BranchAttendanceQrService {
  Future<BranchAttendanceQr> fetch({
    required String branchId,
    required String organizationUID,
    bool regenerate = false,
  });
}

class FirebaseBranchAttendanceQrService implements BranchAttendanceQrService {
  FirebaseBranchAttendanceQrService([FirebaseFunctions? functions])
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<BranchAttendanceQr> fetch({
    required String branchId,
    required String organizationUID,
    bool regenerate = false,
  }) async {
    final result = await _functions
        .httpsCallable(
          'branchAttendanceQr',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        )
        .call<dynamic>({
          'branchId': branchId,
          'organizationUID': organizationUID,
          'regenerate': regenerate,
        });
    return BranchAttendanceQr.fromCallable(result.data);
  }
}
