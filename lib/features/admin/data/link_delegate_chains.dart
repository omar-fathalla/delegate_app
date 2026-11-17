import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Shared logic of the «ربط بسلاسل إضافية» flow: the mobile
/// [LinkDelegateToOrgSheet] and the HR web «إضافة سلاسل» dialog both use it,
/// so the chain list and the add_organization request stay identical.

/// A company chain the delegate can be linked to. [alreadyLinked] is only
/// ever true when [fetchLinkableChains] is called with `includeLinked`.
class LinkableChain {
  const LinkableChain({
    required this.uid,
    required this.name,
    this.alreadyLinked = false,
  });

  final String uid;
  final String name;
  final bool alreadyLinked;

  ChainOption get option => ChainOption(uid: uid, name: name);
}

String linkRequestCompanyUID({
  required Delegate delegate,
  required Delegate supervisor,
}) =>
    supervisor.companyUID.isNotEmpty ? supervisor.companyUID : delegate.companyUID;

String linkRequestCompanyName({
  required Delegate delegate,
  required Delegate supervisor,
}) =>
    supervisor.companyName.isNotEmpty ? supervisor.companyName : delegate.companyName;

/// The company's chains for [delegate], with the sheet's original rules:
/// Fathalla chains are hidden, the chain must contain the company, and an
/// organization admin only sees their own chain.
///
/// By default chains the delegate is already on are left out (the mobile
/// sheet). With [includeLinked] they are returned with `alreadyLinked`.
Future<List<LinkableChain>> fetchLinkableChains({
  required FirebaseFirestore firestore,
  required Delegate delegate,
  required Delegate supervisor,
  bool includeLinked = false,
}) async {
  final snap = await firestore.collection('organizations').get();

  final currentOrgUID = delegate.organizationUID.trim().toLowerCase();
  final currentOrgName = delegate.organizationName.trim().toLowerCase();
  final allKnownOrgNames =
      delegate.allOrganizationNames.map((n) => n.trim().toLowerCase()).toSet();
  final alreadyUids = {currentOrgUID}..removeWhere((id) => id.isEmpty);

  final companyUID = (supervisor.companyUID.isNotEmpty
          ? supervisor.companyUID
          : delegate.companyUID)
      .trim();
  final role = supervisor.role;
  final isGlobal = role == UserRole.superAdmin;
  if (companyUID.isEmpty && !isGlobal) return const [];

  final orgs = <LinkableChain>[];
  for (final doc in snap.docs) {
    final data = doc.data();
    final uid = doc.id;
    final name = (data['name'] ?? data['title'] ?? doc.id).toString();
    final uidKey = uid.trim().toLowerCase();
    final nameKey = name.trim().toLowerCase();
    final isFathalla = nameKey.contains('fathalla') ||
        nameKey.contains('فتح الله') ||
        nameKey.contains('فتح_الله') ||
        uidKey.contains('fathalla') ||
        uidKey.contains('فتح_الله');
    if (isFathalla) continue;
    final linked = alreadyUids.contains(uidKey) ||
        nameKey == currentOrgName ||
        allKnownOrgNames.contains(nameKey);
    if (linked && !includeLinked) continue;
    if (companyUID.isNotEmpty) {
      try {
        final cDoc = await firestore
            .collection('organizations')
            .doc(uid)
            .collection('companies')
            .doc(companyUID)
            .get();
        if (!cDoc.exists) continue;
      } catch (_) {
        continue;
      }
    }
    orgs.add(LinkableChain(uid: uid, name: name, alreadyLinked: linked));
  }
  if (role == UserRole.organizationAdmin) {
    final ownOrg = supervisor.organizationUID.trim();
    orgs.removeWhere((o) => o.uid.trim() != ownOrg);
  }
  return orgs;
}

/// Writes the same add_organization `delegate_requests` doc as the sheet:
/// first chain is the target, the rest go in organizationUIDs, and there is
/// no fee (one subscription per delegate covers every chain).
Future<Either<Failure, String>> submitLinkChainsRequest({
  required DelegateSubscriptionRepository repo,
  required Delegate delegate,
  required Delegate supervisor,
  required List<ChainOption> selected,
}) {
  final primary = selected.first;
  final extra = selected.skip(1).toList();
  return repo.submitAddOrganizationRequest(
    supervisorUid: supervisor.uid,
    supervisorName: supervisor.fullName,
    supervisorPhone: supervisor.phoneNumber,
    companyUID: linkRequestCompanyUID(delegate: delegate, supervisor: supervisor),
    companyName: linkRequestCompanyName(delegate: delegate, supervisor: supervisor),
    targetOrganizationUID: primary.uid,
    targetOrganizationName: primary.name,
    organizationUIDs: [for (final c in extra) c.uid],
    organizationNames: [for (final c in extra) c.name],
    existingDelegate: delegate,
    // One subscription per delegate covers all chains: no fee here.
    paymentMethod: SubscriptionPaymentMethod.notRequired,
    fee: 0,
    remainingMonths: 0,
  );
}

String linkChainsSuccessMessage(List<String> names) =>
    'تم إرسال طلب ربط المندوب بـ ${names.length} سلسلة (${names.join('، ')}) بنجاح (بدون رسوم إضافية)! بانتظار الاعتماد.';

const String kLinkChainsRequiredMessage = 'يرجى اختيار سلسلة واحدة على الأقل.';

const String kLinkChainsNoneAvailableMessage =
    'لا توجد منظمات إضافية متاحة للربط حالياً (المندوب مشترك في جميع المنظمات المتاحة).';
