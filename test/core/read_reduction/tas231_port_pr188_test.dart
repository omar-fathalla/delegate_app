// TAS-231: the parts of PR #188 (Firestore read reduction) ported to dev.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/services/delegate_profile_cache.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.label, this.mounts);
  final String label;
  final List<String> mounts;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.mounts.add(widget.label);
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

Widget _host(int index, List<String> mounts, {required bool lazy}) =>
    MaterialApp(
      home: M3FadeThroughIndexedStack(
        index: index,
        lazy: lazy,
        children: [
          _Probe('a', mounts),
          _Probe('b', mounts),
          _Probe('c', mounts),
        ],
      ),
    );

void main() {
  group('M3FadeThroughIndexedStack lazy tabs', () {
    testWidgets('lazy: only visited tabs mount, and stay mounted',
        (tester) async {
      final mounts = <String>[];
      await tester.pumpWidget(_host(0, mounts, lazy: true));
      expect(mounts, ['a']);

      await tester.pumpWidget(_host(2, mounts, lazy: true));
      await tester.pumpAndSettle();
      expect(mounts, ['a', 'c']);

      // Back to a visited tab: nothing re-mounts, b is still never built.
      await tester.pumpWidget(_host(0, mounts, lazy: true));
      await tester.pumpAndSettle();
      expect(mounts, ['a', 'c']);
    });

    testWidgets('default (not lazy) still builds every tab', (tester) async {
      final mounts = <String>[];
      await tester.pumpWidget(_host(0, mounts, lazy: false));
      expect(mounts, ['a', 'b', 'c']);
    });
  });

  group('company name session memo', () {
    const orgId = 'org_tas231';
    const companyId = 'company_tas231';
    const branch = 'سموحة';
    late FakeFirebaseFirestore db;
    late MarketingRemoteDataSourceImpl dataSource;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      DelegateProfileCache.clearSession();
      MarketingRemoteDataSourceImpl.debugClearCompanyNameCache();
      db = FakeFirebaseFirestore();
      dataSource = MarketingRemoteDataSourceImpl(
        firestore: db,
        profileCache: DelegateProfileCache(prefs: prefs),
      );
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      await db.collection(kAttendanceCollection).doc('in1').set({
        'type': 'check_in',
        'branchName': branch,
        'delegateId': 'd1',
        'timestamp': Timestamp.fromDate(start.add(const Duration(hours: 9))),
        'organizationId': orgId,
        'companyId': companyId,
        'delegateName': 'Delegate d1',
        'phoneNumber': '01000000000',
      });
      await db
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(companyId)
          .set({'name': 'Test Co'});
    });

    Future<String?> companyNameOnReload() async {
      final now = DateTime.now();
      final result = await dataSource.getTodayAttendanceForBranches(
        branchNames: [branch],
        organizationId: orgId,
        date: DateTime(now.year, now.month, now.day),
      );
      return result[branch]?.first['companyName'] as String?;
    }

    Future<void> removeCompanyDoc() => db
        .collection('organizations')
        .doc(orgId)
        .collection('companies')
        .doc(companyId)
        .delete();

    test('a reload reuses the name instead of reading the company doc again',
        () async {
      expect(await companyNameOnReload(), 'Test Co');
      // If the second reload read the company doc, the name would be gone.
      await removeCompanyDoc();
      expect(await companyNameOnReload(), 'Test Co');
    });

    test('control: without the memo the second reload reads the doc again',
        () async {
      expect(await companyNameOnReload(), 'Test Co');
      await removeCompanyDoc();
      MarketingRemoteDataSourceImpl.debugClearCompanyNameCache();
      expect(await companyNameOnReload(), isNot('Test Co'));
    });
  });
}
