import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_audit_edit_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_capture_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_kpi_card.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_month_calendar.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_rest_day_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_review_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_audit_tile.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
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

  testWidgets('PrivateLabelKpiCard renders onOpenCatalog button in full mode even when kpi is null', (tester) async {
    var tappedFull = false;
    var tappedCompact = false;

    await tester.pumpWidget(_host(Column(
      children: [
        PrivateLabelKpiCard(
          kpi: null,
          compact: false,
          isLoading: true,
          onOpenCatalog: () => tappedFull = true,
          catalogButtonLabel: 'تصفح الكتالوج (للنظر فقط)',
        ),
        const SizedBox(height: 16),
        PrivateLabelKpiCard(
          kpi: null,
          compact: true,
          isLoading: true,
          onOpenCatalog: () => tappedCompact = true,
          catalogButtonLabel: 'الكتالوج (للنظر فقط)',
        ),
      ],
    )));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('تصفح الكتالوج (للنظر فقط)'), findsOneWidget);
    expect(find.text('الكتالوج (للنظر فقط)'), findsOneWidget);

    await tester.tap(find.text('تصفح الكتالوج (للنظر فقط)'));
    await tester.tap(find.text('الكتالوج (للنظر فقط)'));
    expect(tappedFull, isTrue);
    expect(tappedCompact, isTrue);
  });

  testWidgets('PrivateLabelKpiCard renders English "Catalog" button label in compact mode', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(
      PrivateLabelKpiCard(
        kpi: _kpi(),
        compact: true,
        isLoading: false,
        onOpenCatalog: () => tapped = true,
        catalogButtonLabel: 'Catalog',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Catalog'), findsOneWidget);
    await tester.tap(find.text('Catalog'));
    expect(tapped, isTrue);
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

  testWidgets('edit sheet selects product from dropdown menu, updates barcode on switch, and edits price', (tester) async {
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
      productId: 'default_wixmax',
      productName: 'wixmax',
      barcode: '62245165342547',
      referencePrice: 58,
      shelfPrice: 58,
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

    // Ensure there is NO manual product name TextField
    expect(find.text('اسم المنتج *'), findsNothing);
    expect(find.byType(PrivateLabelProductDropdownMenu), findsOneWidget);

    // Switch product via dropdown from wixmax to أرز فتح الله 1 كيلو
    await tester.tap(find.byType(PrivateLabelProductDropdownMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أرز فتح الله 1 كيلو').last);
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(3)); // Price, Barcode, Notes

    // Edit price field (now first TextField)
    await tester.enterText(textFields.at(0), '35.5');
    await tester.pumpAndSettle();

    await tester.tap(find.text('حفظ التعديلات'));
    await tester.pumpAndSettle();

    expect(updatedAudit, isNotNull);
    expect(updatedAudit?.productName, 'أرز فتح الله 1 كيلو');
    expect(updatedAudit?.productId, 'default_fathalla_rice_1kg');
    expect(updatedAudit?.referencePrice, 35.0);
    expect(updatedAudit?.barcode, '6224001001015');
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

  test('PrivateLabelProduct.defaultCatalog returns 4 products with images, prices, and barcodes', () {
    final catalog = PrivateLabelProduct.defaultCatalog('org1');
    expect(catalog.length, 4);
    expect(catalog.map((p) => p.name), containsAll([
      'wixmax',
      'أرز فتح الله 1 كيلو',
      'سكر فتح الله 1 كيلو',
      'زيت خليط فتح الله 1 لتر',
    ]));
    for (final p in catalog) {
      expect(p.referencePrice, isNotNull);
      expect(p.referencePrice! > 0, isTrue);
      expect(p.barcode, isNotNull);
      expect(p.barcode!.isNotEmpty, isTrue);
      expect(p.imageUrl, isNotNull);
      expect(p.imageUrl!.startsWith('assets/images/private_label/'), isTrue);
    }
  });

  testWidgets('PrivateLabelCaptureSheet selects product from dropdown menu instead of manual typing', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    PrivateLabelAuditDraft? savedDraft;
    final catalog = PrivateLabelProduct.defaultCatalog('org1');

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  savedDraft = await showPrivateLabelSheet<PrivateLabelAuditDraft>(
                    context: context,
                    heightFactor: 0.9,
                    builder: (_, layout) => PrivateLabelCaptureSheet(
                      layout: layout,
                      initialProductPath: 'assets/images/private_label/wixmax.jpg',
                      initialPricePath: 'assets/images/private_label/wixmax.jpg',
                      branches: const ['فرع سموحة'],
                      initialBranch: 'فرع سموحة',
                      products: catalog,
                      organizationUID: 'org1',
                      companyUID: 'comp1',
                      delegateUid: 'u1',
                      delegateName: 'Omar',
                      clock: () => _today,
                    ),
                  );
                },
                child: const Text('open_capture'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open_capture'));
    await tester.pumpAndSettle();

    // Open product dropdown menu
    expect(find.text('اختار المنتج من الكتالوج'), findsOneWidget);
    await tester.tap(find.text('اختار المنتج من الكتالوج'));
    await tester.pumpAndSettle();

    // Select 'أرز فتح الله 1 كيلو' from dropdown menu
    await tester.tap(find.text('أرز فتح الله 1 كيلو').last);
    await tester.pumpAndSettle();

    // Enter shelf price
    await tester.enterText(find.byType(TextField).first, '35');
    await tester.pumpAndSettle();

    // Save draft
    await tester.tap(find.text('حفظ التوثيق'));
    await tester.pumpAndSettle();

    expect(savedDraft, isNotNull);
    expect(savedDraft?.productName, 'أرز فتح الله 1 كيلو');
    expect(savedDraft?.productId, 'default_fathalla_rice_1kg');
    expect(savedDraft?.referencePrice, 35.0);
    expect(savedDraft?.shelfPrice, 35.0);
    expect(savedDraft?.barcode, '6224001001015');
  });
}

