import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/data/company_chains.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// The company's own «طلب ضم سلسلة» history for the HR web page
/// «طلبات السلاسل» tab (TAS-118).
///
/// Same company scope as [fetchPendingCompanyChainUids]: one equality on
/// `companyUID`, every status, so HR can also see approved and rejected
/// requests and the reviewer's reason. The existing read rule
/// (`isCompanyScopedStaff() && companyUID == callerCompany()`) already
/// covers this query; no rule change and no composite index.
Stream<List<CompanyChainRequest>> watchCompanyChainRequestsForCompany({
  required FirebaseFirestore firestore,
  required String companyUID,
}) {
  final co = companyUID.trim();
  if (co.isEmpty) return Stream.value(const <CompanyChainRequest>[]);
  return firestore
      .collection(kCompanyChainRequestsCollection)
      .where('companyUID', isEqualTo: co)
      .snapshots()
      .map((s) => sortCompanyChainRequestsNewestFirst(
            s.docs.map(CompanyChainRequest.fromDoc).toList(),
          ));
}

/// Newest first. A request whose server timestamp has not landed yet
/// (createdAt still null) was just sent, so it goes on top.
List<CompanyChainRequest> sortCompanyChainRequestsNewestFirst(
  List<CompanyChainRequest> list,
) {
  final copy = [...list];
  copy.sort((a, b) {
    final ac = a.createdAt;
    final bc = b.createdAt;
    if (ac == null && bc == null) {
      return a.organizationName.compareTo(b.organizationName);
    }
    if (ac == null) return -1;
    if (bc == null) return 1;
    final c = bc.compareTo(ac);
    return c != 0 ? c : a.organizationName.compareTo(b.organizationName);
  });
  return copy;
}

/// Company-scoped staff who sent the requests and may read them back
/// under the current rules. Reviewers (super admin, technical support,
/// chain admin) keep the decision panel instead.
bool canViewCompanyChainRequestHistory(Delegate viewer) {
  if (viewer.companyUID.trim().isEmpty) return false;
  return viewer.role == UserRole.admin ||
      viewer.role == UserRole.hr ||
      viewer.role == UserRole.accountant ||
      viewer.role == UserRole.branchesMarketingManager;
}
