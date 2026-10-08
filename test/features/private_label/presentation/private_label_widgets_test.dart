import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_audit_edit_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_kpi_card.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_month_calendar.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_rest_day_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_review_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_audit_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 10, 7, 10);

List<PrivateLabelDay> _days() => [
      for (var d = 1; d <= 6; d++)
        PrivateLabelDay(
          id: 'u1_$d',
          organizationUID: 'org',
          companyUID: '',
          delegateUid: 'u1',
          delegateName: 'Omar',
          date: PrivateLabelDates.dayKey(DateTime(2026, 10, d)),
          month: '2026-10',
          type: d == 3 ? PrivateLabelDayType.rest : PrivateLabelDayType.worked,
          auditsCount: d == 3 ? 0 : 2,
        ),
    ];

PrivateLabelKpi _kpi() => PrivateLabelKpi.calculate(
      year: 2026,
      month: 10,
      days: _days(),
      restAllowance: 4,
      today: _today,
    );

Widget _host(Widget child, {double width = 390}) => MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1B5E20)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 844)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('KPI card renders compact + full without overflow (phone width)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(Column(
      children: [
        PrivateLabelKpiCard(kpi: _kpi(), compact: true, isLoading: false, isSyncing: false, pendingCount: 2, onOpen: () {}),
        const SizedBox(height: 16),
        PrivateLabelKpiCard(kpi: _kpi(), isLoading: false, isSyncing: false, pendingCount: 0, onRegisterRestToday: () {}),
        const SizedBox(height: 16),
        const PrivateLabelKpiCard(kpi: null, isLoading: true, isSyncing: false, pendingCount: 0),
      ],
    )));
    // The loading variant animates forever, so pump fixed frames instead of settling.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(PrivateLabelKpiCard), findsNWidgets(3));
  });

  testWidgets('month calendar renders and reports taps', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? tapped;
    await tester.pumpWidget(_host(PrivateLabelMonthCalendar(
      year: 2026,
      month: 10,
      days: _days(),
      today: _today,
      selectedDate: '2026-10-07',
      onDaySelected: (d) => tapped = d,
      onPreviousMonth: () {},
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('5').first);
    expect(tapped, '2026-10-05');
  });

  testWidgets('rest-day confirm sheet returns true on confirm', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await confirmPrivateLabelRestDay(
                  context: context,
                  date: '2026-10-07',
                  remainingRestDays: 3,
                  restAllowance: 4,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('تأكيد الإجازة'), findsOneWidget);

    await tester.tap(find.text('تأكيد الإجازة'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('review sheet requires notes for rejection', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final audit = PrivateLabelAudit(
      id: 'a1',
      organizationUID: 'org',
      companyUID: '',
      delegateUid: 'u1',
      delegateName: 'Omar',
      branchName: 'فرع المعادي',
      productName: 'أرز فتح الله 1 كجم',
      referencePrice: 30,
      shelfPrice: 32.5,
      stockStatus: PrivateLabelStockStatus.low,
      productPhotoUrl: '',
      pricePhotoUrl: '',
      auditDate: '2026-10-07',
      auditMonth: '2026-10',
      capturedAt: _today,
    );

    PrivateLabelReviewDecision? decision;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                decision = await showPrivateLabelReviewSheet(context: context, audit: audit);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Price mismatch → defaults to "price issue".
    expect(find.text('تسجيل مخالفة سعر'), findsOneWidget);

    // Switch to reject: primary action disabled until a reason is typed.
    await tester.ensureVisible(find.text('مرفوض').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مرفوض').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('رفض التوثيق'));
    await tester.pumpAndSettle();
    expect(decision, isNull);

    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'الصورة مش واضحة');
    await tester.pumpAndSettle();
    await tester.tap(find.text('رفض التوثيق'));
    await tester.pumpAndSettle();
    expect(decision?.status, PrivateLabelReviewStatus.rejected);
    expect(decision?.notes, 'الصورة مش واضحة');
  });

  testWidgets('delete confirm sheet returns true on confirmation', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final audit = PrivateLabelAudit(
      id: 'a1',
      organizationUID: 'org',
      companyUID: '',
      delegateUid: 'u1',
      delegateName: 'Omar',
      branchName: 'فرع المعادي',
      productName: 'أرز 1 كجم',
      shelfPrice: 30,
      stockStatus: PrivateLabelStockStatus.available,
      productPhotoUrl: '',
      pricePhotoUrl: '',
      auditDate: '2026-10-07',
      auditMonth: '2026-10',
      capturedAt: _today,
    );

    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await confirmPrivateLabelAuditDeletion(
                  context: context,
                  audit: audit,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('حذف التوثيق'), findsOneWidget);
    expect(find.text('حذف نهائي'), findsOneWidget);

    await tester.tap(find.text('حذف نهائي'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('edit sheet allows editing product name and price', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final audit = PrivateLabelAudit(
      id: 'a1',
      organizationUID: 'org',
      companyUID: '',
      delegateUid: 'u1',
      delegateName: 'Omar',
      branchName: 'فرع المعادي',
      productName: 'أرز 1 كجم',
      shelfPrice: 30,
      stockStatus: PrivateLabelStockStatus.available,
      productPhotoUrl: '',
      pricePhotoUrl: '',
      auditDate: '2026-10-07',
      auditMonth: '2026-10',
      capturedAt: _today,
    );

    PrivateLabelAudit? updatedAudit;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                updatedAudit = await showPrivateLabelAuditEditSheet(
                  context: context,
                  audit: audit,
                  products: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل بيانات التوثيق'), findsOneWidget);

    final textFields = find.byType(TextField);
    expect(textFields, findsWidgets);

    // Edit price field
    await tester.enterText(textFields.at(1), '35.5');
    await tester.pumpAndSettle();

    await tester.tap(find.text('حفظ التعديلات'));
    await tester.pumpAndSettle();

    expect(updatedAudit, isNotNull);
    expect(updatedAudit?.shelfPrice, 35.5);
  });

  testWidgets('PrivateLabelAuditTile renders single thumb, count badge, product info, price and bottom row', (tester) async {
    final audit = PrivateLabelAudit(
      id: 'a1',
      organizationUID: 'org',
      companyUID: '',
      delegateUid: 'u1',
      delegateName: 'صبحى قاسم سليم',
      branchName: 'Abo Yousif',
      productName: 'Wixi',
      shelfPrice: 14.50,
      stockStatus: PrivateLabelStockStatus.available,
      productPhotoUrl: 'https://example.com/p1.jpg',
      pricePhotoUrl: 'https://example.com/p2.jpg',
      reviewStatus: PrivateLabelReviewStatus.pending,
      auditDate: '2026-10-07',
      auditMonth: '2026-10',
      capturedAt: DateTime(2026, 10, 7, 15, 3),
    );

    await tester.pumpWidget(_host(PrivateLabelAuditTile(
      audit: audit,
      showDelegate: true,
      onTap: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Wixi'), findsOneWidget);
    expect(find.text('14.50 ج.م'), findsOneWidget);
    expect(find.textContaining('صبحى قاسم سليم'), findsOneWidget);
    expect(find.text('في انتظار المراجعة'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });
}

