import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';

abstract class MarketingRemoteDataSource {
  Future<List<Map<String, dynamic>>> getCompanies(String organizationUID);

  /// Get companies with pagination
  /// [lastDocument] is the last document from previous page (for pagination)
  /// [limit] is the number of companies to fetch (default 20)
  Future<Map<String, dynamic>> getCompaniesPaginated(
    String organizationUID, {
    DocumentSnapshot? lastDocument,
    int limit = 20,
  });

  Future<List<DelegateModel>> getDelegates(
    String organizationUID,
    String? companyUID,
  );
}

class MarketingRemoteDataSourceImpl implements MarketingRemoteDataSource {
  final FirebaseFirestore firestore;

  MarketingRemoteDataSourceImpl({required this.firestore});

  @override
  Future<List<Map<String, dynamic>>> getCompanies(
    String organizationUID,
  ) async {
    try {
      final snapshot = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .get();

      // Get list of companies with their data
      final companies = snapshot.docs
          .map((doc) => {'uid': doc.id, ...doc.data()})
          .toList();

      // For each company, try to find the marketing user
      for (var company in companies) {
        try {
          // Query users collection for marketing user in this company
          final userQuery = await firestore
              .collection('users')
              .where('organizationUID', isEqualTo: organizationUID)
              .where('companyUID', isEqualTo: company['uid'])
              .where('role', isEqualTo: 'marketing')
              .limit(1)
              .get();

          if (userQuery.docs.isNotEmpty) {
            final userData = userQuery.docs.first.data();
            company['marketingUserName'] =
                userData['displayName'] ?? 'موظف تسويق';
          } else {
            company['marketingUserName'] = null;
          }
        } catch (_) {
          // If query fails, continue without marketing user name
          company['marketingUserName'] = null;
        }
      }

      return companies;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب قائمة الشركات.');
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع.');
    }
  }

  @override
  Future<Map<String, dynamic>> getCompaniesPaginated(
    String organizationUID, {
    DocumentSnapshot? lastDocument,
    int limit = 20,
  }) async {
    try {
      // Build query with pagination
      Query query = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .orderBy('name') // Order by name for consistent pagination
          .limit(limit + 1); // Fetch one extra to check if there are more

      // If we have a last document, start after it
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.get();

      // Check if there are more companies
      final hasMore = snapshot.docs.length > limit;
      final docs = hasMore ? snapshot.docs.take(limit).toList() : snapshot.docs;

      // Get list of companies with their data
      final companies = docs
          .map((doc) => {'uid': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();

      // For each company, try to find the marketing user
      for (var company in companies) {
        try {
          // Query users collection for marketing user in this company
          final userQuery = await firestore
              .collection('users')
              .where('organizationUID', isEqualTo: organizationUID)
              .where('companyUID', isEqualTo: company['uid'])
              .where('role', isEqualTo: 'marketing')
              .limit(1)
              .get();

          if (userQuery.docs.isNotEmpty) {
            final userData = userQuery.docs.first.data();
            company['marketingUserName'] =
                userData['displayName'] ?? 'موظف تسويق';
          } else {
            company['marketingUserName'] = null;
          }
        } catch (_) {
          // If query fails, continue without marketing user name
          company['marketingUserName'] = null;
        }
      }

      return {
        'companies': companies,
        'hasMore': hasMore,
        'lastDocument': docs.isNotEmpty ? docs.last : null,
      };
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب قائمة الشركات.');
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع.');
    }
  }

  @override
  Future<List<DelegateModel>> getDelegates(
    String organizationUID,
    String? companyUID,
  ) async {
    try {
      if (companyUID != null) {
        final snapshot = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
            .get();
        return snapshot.docs
            .map((doc) => DelegateModel.fromJson(doc.data(), doc.id))
            .toList();
      } else {
        // If companyUID is null, fetch all delegates in the organization
        // We can do this via collectionGroup 'delegates' where organizationUID matches
        final snapshot = await firestore
            .collectionGroup('delegates')
            .where('organizationUID', isEqualTo: organizationUID)
            .get();
        return snapshot.docs
            .map((doc) => DelegateModel.fromJson(doc.data(), doc.id))
            .toList();
      }
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب المندوبين.');
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع.');
    }
  }
}
