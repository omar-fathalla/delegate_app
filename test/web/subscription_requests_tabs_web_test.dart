// HR web «طلبات الاشتراك»: tabs, filter chips, chain requests table and
// empty states (TAS-118, TAS-142). Fake data only.
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/data/company_chain_request_history.dart';
import 'package:delegate_app/features/admin/data/company_chains.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/web/hr_system/company_chain_requests_history.dart';
import 'package:delegate_app/web/hr_system/delegate_subscription_requests_web.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _co = 'seed-fake-co';
const _otherCo = 'seed-fake-other-co';

Delegate _staff(UserRole role, {String companyUID = _co}) => Delegate(
      uid: 'seed-fake-${role.name}',
      firstName: 'مشرف',
      middleName: '',
      lastName: '',
      fullName: 'مشرف تجريبي',
      nationalityID: '',
      motherName: '',
      city: '',
      phoneNumber: '01000000000',
      gender: DelegateGender.male,
      position: DelegatePosition.supervisor,
      birthDate: DateTime(1995),
      organizationUID: '',
      organizationName: '',
      companyUID: companyUID,
      companyName: 'شركة ألفا التجريبية',
      status: DelegateStatus.active,
      delegatePublicId: '',
      allReceiptCodes: const [],
      createdAt: DateTime(2026),
      createdBy: 'test',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: role,
    );

DelegateSubscriptionRequest _sub(
  String id,
  SubscriptionRequestStatus status, {
  String name = 'أحمد سمير حسن',
}) =>
    DelegateSubscriptionRequest(
      id: id,
      supervisorUid: 'seed-fake-hr',
      supervisorName: 'مشرف تجريبي',
      supervisorPhone: '01000000000',
      companyUID: _co,
      companyName: 'شركة ألفا التجريبية',
      organizationUID: 'o-fake',
      organizationName: 'Fake Chain',
      firstName: name.split(' ').first,
      secondName: '',
      thirdName: '',
      fullName: name,
      phoneNumber: '01011111111',
      nationalId: '29501010101010',
      profileImageUrl: '',
      nationalIdFrontUrl: '',
      nationalIdBackUrl: '',
      paymentMethod: SubscriptionPaymentMethod.paymob,
      subscriptionCycle: '2026',
      cycleStartDate: DateTime(2026),
      cycleEndDate: DateTime(2026, 12, 31),
      status: status,
      createdAt: DateTime(2026, 11, 1),
    );

CompanyChainRequest _chain(
  String id,
  String status,
  String name, {
  DateTime? at,
  String? reason,
}) =>
    CompanyChainRequest(
      id: id,
      status: status,
      companyUID: _co,
      companyName: 'شركة ألفا التجريبية',
      organizationUID: 'o-$id',
      organizationName: name,
      supervisorUid: 'seed-fake-hr',
      supervisorName: 'مشرف تجريبي',
      batchId: 'b1',
      createdAt: at,
      rejectionReason: reason,
    );

final _chains = [
  _chain('c1', 'pending', 'Fake Chain Gamma', at: DateTime(2026, 11, 21)),
  _chain('c2', 'pending', 'Fake Chain Beta', at: DateTime(2026, 11, 19)),
  _chain('c3', 'approved', 'Fake Test Organization', at: DateTime(2026, 11, 2)),
  _chain('c4', 'rejected', 'Fake Chain Delta',
      at: DateTime(2026, 10, 28), reason: 'السلسلة غير متاحة في مدينتك'),
];

Future<void> _pump(
  WidgetTester t,
  Widget page, {
  Size size = const Size(1440, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: Directionality(textDirection: TextDirection.rtl, child: page),
    ),
  );
  await t.pumpAndSettle();
}

DelegateSubscriptionRequestsWeb _page({
  UserRole role = UserRole.hr,
  List<DelegateSubscriptionRequest>? subs,
  List<CompanyChainRequest>? chains,
  FirebaseFirestore? firestore,
  SubscriptionRequestsWebTab initialTab = SubscriptionRequestsWebTab.delegates,
  bool showAll = false,
}) =>
    DelegateSubscriptionRequestsWeb(
      currentAdmin: _staff(role),
      onApprove: (_) async => null,
      onReject: (_) async => null,
      requestsOverride: subs ?? const [],
      chainRequestsOverride: firestore == null ? (chains ?? _chains) : null,
      firestore: firestore,
      initialTab: initialTab,
      initialShowAll: showAll,
    );

void main() {
  setUp(() => WebRuntimePolicy.debugIsWebOverride = true);
  tearDown(() {
    WebRuntimePolicy.debugIsWebOverride = null;
    DelegateSubscriptionRequestsWeb.requestedTab.value = null;
  });

  group('tabs', () {
    testWidgets('HR sees both tabs, delegates first', (t) async {
      await _pump(t, _page(subs: [_sub('s1', SubscriptionRequestStatus.pending)]));
      expect(find.byKey(DelegateSubscriptionRequestsWeb.delegatesTabKey), findsOneWidget);
      expect(find.byKey(DelegateSubscriptionRequestsWeb.chainsTabKey), findsOneWidget);
      expect(find.text('اشتراكات المناديب'), findsOneWidget);
      expect(find.text('طلبات السلاسل'), findsOneWidget);
      expect(find.text('أحمد سمير حسن'), findsOneWidget);
      expect(find.byKey(CompanyChainRequestsHistory.tableKey), findsNothing);

      await t.tap(find.byKey(DelegateSubscriptionRequestsWeb.chainsTabKey));
      await t.pumpAndSettle();
      expect(find.byKey(CompanyChainRequestsHistory.tableKey), findsOneWidget);
      expect(find.text('أحمد سمير حسن'), findsNothing);
    });

    testWidgets('initialTab opens «طلبات السلاسل»', (t) async {
      await _pump(t, _page(initialTab: SubscriptionRequestsWebTab.chains));
      expect(find.byKey(CompanyChainRequestsHistory.tableKey), findsOneWidget);
    });

    testWidgets('requestedTab switches a page that is already built', (t) async {
      await _pump(t, _page());
      expect(find.byKey(CompanyChainRequestsHistory.tableKey), findsNothing);
      DelegateSubscriptionRequestsWeb.requestedTab.value =
          SubscriptionRequestsWebTab.chains;
      await t.pumpAndSettle();
      expect(find.byKey(CompanyChainRequestsHistory.tableKey), findsOneWidget);
      expect(DelegateSubscriptionRequestsWeb.requestedTab.value, isNull);
    });

    testWidgets('reviewers keep the single list without tabs', (t) async {
      for (final role in [UserRole.superAdmin, UserRole.technicalSupport]) {
        await _pump(t, _page(role: role));
        expect(find.byKey(DelegateSubscriptionRequestsWeb.chainsTabKey), findsNothing,
            reason: role.name);
        expect(find.byType(TabBar), findsNothing, reason: role.name);
      }
    });

    test('who gets the chains tab', () {
      for (final r in [UserRole.hr, UserRole.admin, UserRole.accountant, UserRole.branchesMarketingManager]) {
        expect(canViewCompanyChainRequestHistory(_staff(r)), isTrue, reason: r.name);
      }
      for (final r in [UserRole.superAdmin, UserRole.technicalSupport, UserRole.organizationAdmin, UserRole.delegate, UserRole.marketing]) {
        expect(canViewCompanyChainRequestHistory(_staff(r)), isFalse, reason: r.name);
      }
      expect(canViewCompanyChainRequestHistory(_staff(UserRole.hr, companyUID: '')), isFalse);
    });
  });

  group('chain requests table', () {
    testWidgets('columns, rows, status chips and the reviewer reply', (t) async {
      await _pump(t, _page(initialTab: SubscriptionRequestsWebTab.chains));
      for (final title in ['السلسلة', 'الفروع المطلوبة', 'تاريخ الطلب', 'رد الإدارة', 'الحالة']) {
        expect(find.byKey(Key('${CompanyChainRequestsHistory.headerKeyPrefix}$title')), findsOneWidget,
            reason: title);
      }
      for (final r in _chains) {
        expect(find.byKey(CompanyChainRequestsHistory.rowKey(r.id)), findsOneWidget);
      }
      // Newest first.
      final gamma = t.getTopLeft(find.text('Fake Chain Gamma')).dy;
      final delta = t.getTopLeft(find.text('Fake Chain Delta')).dy;
      expect(gamma, lessThan(delta));

      HrStatusChip chipOf(String id) => t.widget<HrStatusChip>(find.descendant(
            of: find.byKey(CompanyChainRequestsHistory.rowKey(id)),
            matching: find.byType(HrStatusChip),
          ));
      expect(chipOf('c1').tone, HrStatusTone.warning);
      expect(chipOf('c1').label, 'قيد المراجعة');
      expect(chipOf('c3').tone, HrStatusTone.success);
      expect(chipOf('c3').label, 'مقبول');
      expect(chipOf('c4').tone, HrStatusTone.danger);
      expect(chipOf('c4').label, 'مرفوض');

      expect(find.text('السلسلة غير متاحة في مدينتك'), findsOneWidget);
      expect(find.text('بانتظار رد الإدارة'), findsNWidgets(2));
      expect(find.text('21/11/2026'), findsOneWidget);
      expect(find.text('كل فروع السلسلة'), findsNWidgets(4));
    });

    testWidgets('filter chips: counts, one line, filtering', (t) async {
      await _pump(t, _page(initialTab: SubscriptionRequestsWebTab.chains));
      expect(find.text('الكل 4'), findsOneWidget);
      expect(find.text('قيد المراجعة 2'), findsOneWidget);
      expect(find.text('مقبولة 1'), findsOneWidget);
      expect(find.text('مرفوضة 1'), findsOneWidget);
      final ys = {
        for (final f in [null, ...CompanyChainRequestFilter.values])
          t.getTopLeft(find.byKey(CompanyChainRequestsHistory.filterKey(f))).dy,
      };
      expect(ys.length, 1, reason: 'chips on one line');

      await t.tap(find.byKey(CompanyChainRequestsHistory.filterKey(CompanyChainRequestFilter.rejected)));
      await t.pumpAndSettle();
      expect(find.byKey(CompanyChainRequestsHistory.rowKey('c4')), findsOneWidget);
      expect(find.byKey(CompanyChainRequestsHistory.rowKey('c1')), findsNothing);

      await t.tap(find.byKey(CompanyChainRequestsHistory.filterKey(CompanyChainRequestFilter.pending)));
      await t.pumpAndSettle();
      expect(find.byKey(CompanyChainRequestsHistory.rowKey('c1')), findsOneWidget);
      expect(find.byKey(CompanyChainRequestsHistory.rowKey('c2')), findsOneWidget);
      expect(find.byKey(CompanyChainRequestsHistory.rowKey('c3')), findsNothing);
    });

    testWidgets('empty: no requests, and a filter with no match', (t) async {
      await _pump(t, _page(initialTab: SubscriptionRequestsWebTab.chains, chains: const []));
      expect(find.byKey(CompanyChainRequestsHistory.emptyKey), findsOneWidget);
      expect(find.text('لا توجد طلبات سلاسل'), findsOneWidget);
      expect(find.byKey(CompanyChainRequestsHistory.tableKey), findsNothing);

      await _pump(
        t,
        _page(
          initialTab: SubscriptionRequestsWebTab.chains,
          chains: [_chain('c1', 'pending', 'Fake Chain Gamma', at: DateTime(2026, 11, 21))],
        ),
      );
      await t.tap(find.byKey(CompanyChainRequestsHistory.filterKey(CompanyChainRequestFilter.approved)));
      await t.pumpAndSettle();
      expect(find.byKey(CompanyChainRequestsHistory.filteredEmptyKey), findsOneWidget);
      await t.tap(find.text('عرض كل الطلبات'));
      await t.pumpAndSettle();
      expect(find.byKey(CompanyChainRequestsHistory.rowKey('c1')), findsOneWidget);
    });

    testWidgets('Firestore: only the HR company, every status', (t) async {
      final fs = FakeFirebaseFirestore();
      final col = fs.collection(kCompanyChainRequestsCollection);
      Future<void> add(String id, String co, String status, String name, {String? reason}) =>
          col.doc(id).set({
            'requestType': 'company_join_chain',
            'status': status,
            'companyUID': co,
            'companyName': 'x',
            'organizationUID': 'o-$id',
            'organizationName': name,
            'supervisorUid': 'seed-fake-hr',
            'supervisorName': 'مشرف تجريبي',
            'batchId': 'b1',
            'createdAt': Timestamp.fromDate(DateTime(2026, 11, 20)),
            'rejectionReason': ?reason,
          });
      await add('f1', _co, 'pending', 'Fake Chain One');
      await add('f2', _co, 'approved', 'Fake Chain Two');
      await add('f3', _co, 'rejected', 'Fake Chain Three', reason: 'سبب تجريبي');
      await add('f4', _otherCo, 'pending', 'Fake Other Company Chain');

      await _pump(t, _page(firestore: fs, initialTab: SubscriptionRequestsWebTab.chains));
      expect(find.text('Fake Chain One'), findsOneWidget);
      expect(find.text('Fake Chain Two'), findsOneWidget);
      expect(find.text('Fake Chain Three'), findsOneWidget);
      expect(find.text('سبب تجريبي'), findsOneWidget);
      expect(find.text('Fake Other Company Chain'), findsNothing);
      expect(find.text('الكل 3'), findsOneWidget);
    });
  });

  group('delegates tab (TAS-142)', () {
    testWidgets('detail pane: one empty state, no outlined card', (t) async {
      await _pump(
        t,
        _page(subs: [
          _sub('s1', SubscriptionRequestStatus.pending),
          _sub('s2', SubscriptionRequestStatus.rejected, name: 'منى خالد إبراهيم'),
        ]),
      );
      final empty = find.byKey(DelegateSubscriptionRequestsWeb.detailEmptyKey);
      expect(empty, findsOneWidget);
      expect(find.descendant(of: empty, matching: find.byType(Icon)), findsOneWidget);
      expect(find.text('اختر طلبًا من القائمة لعرض تفاصيله'), findsOneWidget);
      expect(t.widget(empty), isA<HrEmptyState>());
      // The list pane is the only clipped pane; the empty detail has none.
      expect(find.ancestor(of: empty, matching: find.byType(ClipRRect)), findsNothing);
    });

    testWidgets('filter chips stay on one line at both pane widths', (t) async {
      for (final size in const [Size(1440, 900), Size(1000, 800)]) {
        await _pump(t, _page(subs: [_sub('s1', SubscriptionRequestStatus.pending)]), size: size);
        final ys = {
          for (final s in [null, SubscriptionRequestStatus.pending, SubscriptionRequestStatus.approved, SubscriptionRequestStatus.rejected])
            t.getTopLeft(find.byKey(DelegateSubscriptionRequestsWeb.filterKey(s))).dy,
        };
        expect(ys.length, 1, reason: '$size');
      }
    });

    testWidgets('list empty states share one look and formal wording', (t) async {
      await _pump(t, _page(subs: [_sub('s2', SubscriptionRequestStatus.approved)]));
      final pending = find.byKey(DelegateSubscriptionRequestsWeb.pendingEmptyKey);
      expect(pending, findsOneWidget);
      expect(t.widget(pending), isA<HrEmptyState>());
      expect(find.text('لا توجد طلبات قيد المراجعة'), findsOneWidget);
      expect(find.text('مفيش طلبات مستنية مراجعتك'), findsNothing);
      // One empty state on screen: the detail pane stays blank.
      expect(find.byKey(DelegateSubscriptionRequestsWeb.detailEmptyKey), findsNothing);

      await t.tap(find.text('عرض كل الطلبات'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'لا يوجد اسم كهذا');
      await t.pumpAndSettle();
      final none = find.byKey(DelegateSubscriptionRequestsWeb.noMatchesKey);
      expect(none, findsOneWidget);
      expect(t.widget(none), isA<HrEmptyState>());
    });

    testWidgets('sort label uses formal Arabic', (t) async {
      await _pump(t, _page(subs: [_sub('s1', SubscriptionRequestStatus.pending)]));
      expect(find.text('الأحدث أولًا'), findsOneWidget);
      expect(find.text('الأحدث فوق'), findsNothing);
    });
  });

  test('relative time is formal Arabic', () {
    final now = DateTime(2026, 11, 21, 12);
    expect(subscriptionRelativeTime(now.subtract(const Duration(minutes: 5)), now), 'منذ 5 دقائق');
    expect(subscriptionRelativeTime(now.subtract(const Duration(hours: 2)), now), 'منذ ساعتين');
    expect(subscriptionRelativeTime(now.subtract(const Duration(days: 1)), now), 'أمس');
    expect(subscriptionRelativeTime(now.subtract(const Duration(days: 4)), now), 'منذ 4 أيام');
  });
}
