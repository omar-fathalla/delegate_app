import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/marketing/data/services/delegate_profile_cache.dart';

void main() {
  group('MarketingRemoteDataSourceImpl.normalizeBranchName', () {
    test('should normalize Alef variations (أ, إ, آ -> ا)', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('أبو يوسف'), 'ابو يوسف');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('إبراهيمية'), 'ابراهيميه');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('آل ياسين'), 'ال ياسين');
    });

    test('should normalize Ta Marbouta (ة -> ه)', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('سموحة'), 'سموحه');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('العجمي ستار'), 'العجمي ستار');
    });

    test('should normalize Ya and Alif Maqsura (ى -> ي)', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('مستشفى الكبرى'), 'مستشفي الكبري');
    });

    test('should trim leading/trailing whitespace and collapse internal spaces', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('   Abo Yousif   '), 'abo yousif');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('Abo   Yousif'), 'abo yousif');
    });

    test('should lowercase latin branch names', () {
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('ABO YOUSIF'), 'abo yousif');
      expect(MarketingRemoteDataSourceImpl.normalizeBranchName('Branch Alpha'), 'branch alpha');
    });
  });

  group('MarketingRemoteDataSourceImpl.getTodayAttendanceForBranches', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MarketingRemoteDataSourceImpl dataSource;

    const orgId = 'org_test_001';
    const otherOrgId = 'org_other_999';
    const companyId = 'company_test_001';
    const branch = 'سموحة';

    DateTime dayStart([DateTime? d]) {
      final base = d ?? DateTime.now();
      return DateTime(base.year, base.month, base.day);
    }

    Future<void> seedLog({
      required String type,
      required String branchName,
      required String delegateId,
      required DateTime at,
      required String organizationId,
      String? relatedCheckInId,
      String? docId,
    }) async {
      final ref = docId == null
          ? fakeFirestore.collection(kAttendanceCollection).doc()
          : fakeFirestore.collection(kAttendanceCollection).doc(docId);
      await ref.set({
        'type': type,
        'branchName': branchName,
        'delegateId': delegateId,
        'timestamp': Timestamp.fromDate(at),
        'organizationId': organizationId,
        'companyId': companyId,
        'companyName': 'Test Co',
        'delegateName': 'Delegate $delegateId',
        'phoneNumber': '01000000000',
        'relatedCheckInId': ?relatedCheckInId,
      });
    }

    Future<void> seedDelegate(String delegateId) async {
      await fakeFirestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(companyId)
          .set({'name': 'Test Co'});
      await fakeFirestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(companyId)
          .collection('delegates')
          .doc(delegateId)
          .set({
        'fullName': 'Delegate $delegateId',
        'phoneNumber': '01000000000',
        'companyUID': companyId,
        'organizationUID': orgId,
        'status': 'Active',
        'role': 'delegate',
      });
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      DelegateProfileCache.clearSession();
      fakeFirestore = FakeFirebaseFirestore();
      dataSource = MarketingRemoteDataSourceImpl(
        firestore: fakeFirestore,
        profileCache: DelegateProfileCache(prefs: prefs),
      );
    });

    test('returns only today check-ins for the org and ignores history + other orgs',
        () async {
      final today = dayStart();
      final yesterday = today.subtract(const Duration(days: 1));

      await seedDelegate('d1');
      await seedDelegate('d2');

      // Today, correct org — should appear
      await seedLog(
        type: 'check_in',
        branchName: branch,
        delegateId: 'd1',
        at: today.add(const Duration(hours: 9)),
        organizationId: orgId,
        docId: 'today_in_d1',
      );
      await seedLog(
        type: 'check_out',
        branchName: branch,
        delegateId: 'd1',
        at: today.add(const Duration(hours: 14)),
        organizationId: orgId,
        relatedCheckInId: 'today_in_d1',
      );

      // Yesterday history — must NOT appear
      await seedLog(
        type: 'check_in',
        branchName: branch,
        delegateId: 'd1',
        at: yesterday.add(const Duration(hours: 9)),
        organizationId: orgId,
      );

      // Today but other org — must NOT appear
      await seedLog(
        type: 'check_in',
        branchName: branch,
        delegateId: 'd2',
        at: today.add(const Duration(hours: 10)),
        organizationId: otherOrgId,
      );

      final result = await dataSource.getTodayAttendanceForBranches(
        branchNames: [branch],
        organizationId: orgId,
        date: today,
      );

      expect(result[branch], isNotNull);
      expect(result[branch]!.length, 1);
      expect(result[branch]!.first['delegateId'], 'd1');
      expect(result[branch]!.first['checkOutTime'], isNotNull);
    });

    test('matches spelling-variant branchName (ة/ه) via whereIn variants', () async {
      final today = dayStart();
      await seedDelegate('d3');

      // Stored with ة, queried as ه-normalized favorite name سموحة
      await seedLog(
        type: 'check_in',
        branchName: 'سموحه', // ha instead of ta marbouta
        delegateId: 'd3',
        at: today.add(const Duration(hours: 8, minutes: 30)),
        organizationId: orgId,
      );

      final result = await dataSource.getTodayAttendanceForBranches(
        branchNames: [branch], // سموحة
        organizationId: orgId,
        date: today,
      );

      expect(result[branch]!.length, 1);
      expect(result[branch]!.first['delegateId'], 'd3');
    });

    test('returns empty map for empty branch list without querying', () async {
      final result = await dataSource.getTodayAttendanceForBranches(
        branchNames: const [],
        organizationId: orgId,
      );
      expect(result, isEmpty);
    });

    test('uses denormalized checkOutTime on check-in without needing follow-up logs', () async {
      final today = dayStart();
      await seedDelegate('d4');

      await fakeFirestore.collection(kAttendanceCollection).doc('in_d4').set({
        'type': 'check_in',
        'branchName': branch,
        'delegateId': 'd4',
        'timestamp': Timestamp.fromDate(today.add(const Duration(hours: 9))),
        'organizationId': orgId,
        'companyId': companyId,
        'companyName': 'Test Co',
        'delegateName': 'Delegate d4',
        'phoneNumber': '01000000000',
        'checkOutTime': Timestamp.fromDate(today.add(const Duration(hours: 14))),
        'checkOutDocId': 'out_d4_missing', // no separate check_out doc
        'checkOutLocation': {'latitude': 1.0, 'longitude': 2.0},
      });

      final result = await dataSource.getTodayAttendanceForBranches(
        branchNames: [branch],
        organizationId: orgId,
        date: today,
      );

      expect(result[branch]!.length, 1);
      expect(result[branch]!.first['delegateId'], 'd4');
      expect(result[branch]!.first['checkOutTime'], isNotNull);
    });

    test('first paint from denormalized log fields needs no profile get', () async {
      final today = dayStart();
      // No seedDelegate — only log fields
      await fakeFirestore.collection(kAttendanceCollection).doc('denorm1').set({
        'type': 'check_in',
        'branchName': branch,
        'delegateId': 'd_denorm',
        'timestamp': Timestamp.fromDate(today.add(const Duration(hours: 9))),
        'organizationId': orgId,
        'companyId': companyId,
        'companyName': 'Denorm Co',
        'delegateName': 'Denorm Name',
        'phoneNumber': '01111111111',
        'personalPhotoURL': 'https://example.com/p.jpg',
      });
      await fakeFirestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(companyId)
          .set({'name': 'Denorm Co'});

      Map<String, List<Map<String, dynamic>>>? firstPaint;
      final result = await dataSource.getTodayAttendanceForBranches(
        branchNames: [branch],
        organizationId: orgId,
        date: today,
        onFirstPaint: (p) => firstPaint = p,
      );

      expect(firstPaint, isNotNull);
      expect(firstPaint![branch]!.first['fullName'], 'Denorm Name');
      expect(firstPaint![branch]!.first['phoneNumber'], '01111111111');
      expect(firstPaint![branch]!.first['companyName'], 'Denorm Co');
      expect(firstPaint![branch]!.first['personalPhotoURL'], 'https://example.com/p.jpg');
      expect(result[branch]!.first['fullName'], 'Denorm Name');
    });

    test('legacy log without denorm enriches from profile and never shows مندوب while pending', () async {
      final today = dayStart();
      await seedDelegate('d_legacy');
      await fakeFirestore.collection(kAttendanceCollection).doc('legacy1').set({
        'type': 'check_in',
        'branchName': branch,
        'delegateId': 'd_legacy',
        'timestamp': Timestamp.fromDate(today.add(const Duration(hours: 9))),
        'organizationId': orgId,
        'companyId': companyId,
        // no delegateName / phone / photo
      });

      Map<String, List<Map<String, dynamic>>>? firstPaint;
      final result = await dataSource.getTodayAttendanceForBranches(
        branchNames: [branch],
        organizationId: orgId,
        date: today,
        onFirstPaint: (p) => firstPaint = p,
      );

      expect(firstPaint, isNotNull);
      // While enriching pending, empty name — not the generic مندوب
      expect(firstPaint![branch]!.first['fullName'], isNot(equals('مندوب')));
      expect(result[branch]!.first['fullName'], 'Delegate d_legacy');
      expect(result[branch]!.first['phoneNumber'], '01000000000');
    });

    test('persistent profile cache fills first paint for legacy docs', () async {
      final today = dayStart();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = DelegateProfileCache(prefs: prefs);
      cache.putFromMaps(
        delegateId: 'd_cached',
        fullName: 'Cached Name',
        phoneNumber: '01222222222',
        personalPhotoURL: 'https://example.com/c.jpg',
        companyName: 'Cached Co',
        companyUID: companyId,
        organizationUID: orgId,
      );
      await cache.persist();
      DelegateProfileCache.clearSession();

      dataSource = MarketingRemoteDataSourceImpl(
        firestore: fakeFirestore,
        profileCache: DelegateProfileCache(prefs: prefs),
      );

      await fakeFirestore.collection(kAttendanceCollection).doc('cached1').set({
        'type': 'check_in',
        'branchName': branch,
        'delegateId': 'd_cached',
        'timestamp': Timestamp.fromDate(today.add(const Duration(hours: 9))),
        'organizationId': orgId,
        'companyId': companyId,
      });
      await fakeFirestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(companyId)
          .set({'name': 'Test Co'});

      Map<String, List<Map<String, dynamic>>>? firstPaint;
      await dataSource.getTodayAttendanceForBranches(
        branchNames: [branch],
        organizationId: orgId,
        date: today,
        onFirstPaint: (p) => firstPaint = p,
      );

      expect(firstPaint![branch]!.first['fullName'], 'Cached Name');
      expect(firstPaint![branch]!.first['phoneNumber'], '01222222222');
      expect(firstPaint![branch]!.first['personalPhotoURL'], 'https://example.com/c.jpg');
    });

  });
}
