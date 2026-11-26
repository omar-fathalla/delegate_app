import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:delegate_app/features/admin/data/company_chain_request_history.dart';
import 'package:delegate_app/features/admin/data/company_chains.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';
import 'package:delegate_app/web/hr_system/subscription_filter_chips.dart';

/// Status filter for the «طلبات السلاسل» tab.
enum CompanyChainRequestFilter { pending, approved, rejected }

CompanyChainRequestFilter? companyChainRequestFilterOf(String status) =>
    switch (status) {
      'pending' => CompanyChainRequestFilter.pending,
      'approved' => CompanyChainRequestFilter.approved,
      'rejected' => CompanyChainRequestFilter.rejected,
      _ => null,
    };

/// Status chip: pending = warning, accepted = success, rejected = danger.
({String label, HrStatusTone tone}) companyChainRequestStatusChip(
  String status,
) =>
    switch (companyChainRequestFilterOf(status)) {
      CompanyChainRequestFilter.pending =>
        (label: 'قيد المراجعة', tone: HrStatusTone.warning),
      CompanyChainRequestFilter.approved =>
        (label: 'مقبول', tone: HrStatusTone.success),
      CompanyChainRequestFilter.rejected =>
        (label: 'مرفوض', tone: HrStatusTone.danger),
      null => (label: 'غير معروف', tone: HrStatusTone.neutral),
    };

/// «رد الإدارة» cell text. A rejection shows the reviewer's reason so HR
/// knows why.
String companyChainRequestReply(CompanyChainRequest request) {
  switch (companyChainRequestFilterOf(request.status)) {
    case CompanyChainRequestFilter.pending:
      return 'بانتظار رد الإدارة';
    case CompanyChainRequestFilter.approved:
      return 'تمت الموافقة، وفروع السلسلة متاحة لمناديب الشركة';
    case CompanyChainRequestFilter.rejected:
      final reason = (request.rejectionReason ?? '').trim();
      return reason.isEmpty ? 'تم الرفض دون ذكر سبب' : reason;
    case null:
      return '—';
  }
}

/// Request day as dd/MM/yyyy, «—» while the server time is not set yet.
String companyChainRequestDate(DateTime? at) {
  if (at == null) return '—';
  final l = at.toLocal();
  final d = l.day.toString().padLeft(2, '0');
  final m = l.month.toString().padLeft(2, '0');
  return '$d/$m/${l.year}';
}

/// «طلبات السلاسل» tab on the HR web «طلبات الاشتراك» page (TAS-118):
/// status filter chips and a table of the company's own chain requests.
class CompanyChainRequestsHistory extends StatefulWidget {
  const CompanyChainRequestsHistory({
    super.key,
    required this.companyUID,
    this.firestore,
    this.requestsOverride,
  });

  final String companyUID;
  final FirebaseFirestore? firestore;

  /// Fake data for tests / screenshots; skips Firestore.
  final List<CompanyChainRequest>? requestsOverride;

  static const tableKey = Key('company_chain_history_table');
  static const emptyKey = Key('company_chain_history_empty');
  static const filteredEmptyKey = Key('company_chain_history_filtered_empty');
  static const headerKeyPrefix = 'company_chain_history_header_';
  static Key filterKey(CompanyChainRequestFilter? f) =>
      Key('company_chain_history_filter_${f?.name ?? 'all'}');
  static Key rowKey(String id) => Key('company_chain_history_row_$id');

  static const columns = [
    HrTableColumn('السلسلة', 3),
    HrTableColumn('الفروع المطلوبة', 2),
    HrTableColumn('تاريخ الطلب', 2),
    HrTableColumn('رد الإدارة', 4),
    HrTableColumn('الحالة', 2),
  ];

  @override
  State<CompanyChainRequestsHistory> createState() =>
      _CompanyChainRequestsHistoryState();
}

class _CompanyChainRequestsHistoryState
    extends State<CompanyChainRequestsHistory> {
  CompanyChainRequestFilter? _filter;
  Stream<List<CompanyChainRequest>>? _stream;

  @override
  void initState() {
    super.initState();
    if (widget.requestsOverride == null) _stream = _open();
  }

  Stream<List<CompanyChainRequest>> _open() =>
      watchCompanyChainRequestsForCompany(
        firestore: widget.firestore ?? FirebaseFirestore.instance,
        companyUID: widget.companyUID,
      );

  @override
  Widget build(BuildContext context) {
    final override = widget.requestsOverride;
    if (override != null) {
      return _body(sortCompanyChainRequestsNewestFirst(override));
    }
    return StreamBuilder<List<CompanyChainRequest>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError && !snap.hasData) {
          return HrEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'تعذر تحميل طلبات السلاسل',
            message: 'تحقق من الاتصال ثم أعد المحاولة.',
            action: FilledButton.tonal(
              onPressed: () => setState(() => _stream = _open()),
              child: const Text('إعادة المحاولة'),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _body(snap.data!);
      },
    );
  }

  Widget _body(List<CompanyChainRequest> all) {
    int count(CompanyChainRequestFilter f) =>
        all.where((r) => companyChainRequestFilterOf(r.status) == f).length;
    final shown = _filter == null
        ? all
        : all
            .where((r) => companyChainRequestFilterOf(r.status) == _filter)
            .toList();

    final Widget content;
    if (all.isEmpty) {
      content = const HrEmptyState(
        key: CompanyChainRequestsHistory.emptyKey,
        icon: Symbols.add_business_rounded,
        title: 'لا توجد طلبات سلاسل',
        message: 'ستظهر هنا طلبات ضم السلاسل التي ترسلها الشركة ورد الإدارة عليها.',
      );
    } else if (shown.isEmpty) {
      content = HrEmptyState(
        key: CompanyChainRequestsHistory.filteredEmptyKey,
        icon: Icons.filter_alt_off_rounded,
        title: 'لا توجد طلبات بهذه الحالة',
        action: FilledButton.tonal(
          onPressed: () => setState(() => _filter = null),
          child: const Text('عرض كل الطلبات'),
        ),
      );
    } else {
      content = _table(shown);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubscriptionFilterChipRow<CompanyChainRequestFilter>(
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
            options: [
              SubscriptionFilterOption(
                key: CompanyChainRequestsHistory.filterKey(null),
                label: 'الكل',
                count: all.length,
                value: null,
              ),
              SubscriptionFilterOption(
                key: CompanyChainRequestsHistory.filterKey(
                  CompanyChainRequestFilter.pending,
                ),
                label: 'قيد المراجعة',
                count: count(CompanyChainRequestFilter.pending),
                value: CompanyChainRequestFilter.pending,
              ),
              SubscriptionFilterOption(
                key: CompanyChainRequestsHistory.filterKey(
                  CompanyChainRequestFilter.approved,
                ),
                label: 'مقبولة',
                count: count(CompanyChainRequestFilter.approved),
                value: CompanyChainRequestFilter.approved,
              ),
              SubscriptionFilterOption(
                key: CompanyChainRequestsHistory.filterKey(
                  CompanyChainRequestFilter.rejected,
                ),
                label: 'مرفوضة',
                count: count(CompanyChainRequestFilter.rejected),
                value: CompanyChainRequestFilter.rejected,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _table(List<CompanyChainRequest> rows) {
    const cols = CompanyChainRequestsHistory.columns;
    return HrTableCard(
      key: CompanyChainRequestsHistory.tableKey,
      minWidth: 760,
      builder: (context, width) => Column(
        children: [
          const HrTableHeader(
            columns: cols,
            keyPrefix: CompanyChainRequestsHistory.headerKeyPrefix,
          ),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const HrTableDivider(),
              itemBuilder: (context, i) => _row(context, rows[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, CompanyChainRequest r) {
    final cs = Theme.of(context).colorScheme;
    final chip = companyChainRequestStatusChip(r.status);
    final reply = companyChainRequestReply(r);
    final muted = TextStyle(fontSize: HrFont.body, color: cs.onSurfaceVariant);
    final name = r.organizationName.trim().isEmpty
        ? r.organizationUID
        : r.organizationName.trim();
    return HrTableRow(
      key: CompanyChainRequestsHistory.rowKey(r.id),
      columns: CompanyChainRequestsHistory.columns,
      cells: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.secondaryContainer,
              foregroundColor: cs.onSecondaryContainer,
              child: Text(
                name.isEmpty ? '؟' : name.characters.first.toUpperCase(),
                style: const TextStyle(
                  fontSize: HrFont.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: HrFont.body,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
        // A request covers the whole chain; there is no per-branch request.
        Text('كل فروع السلسلة', style: muted),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            companyChainRequestDate(r.createdAt),
            style: hrTabularStyle(context, color: cs.onSurfaceVariant),
          ),
        ),
        Tooltip(
          message: reply,
          child: Text(
            reply,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
        HrStatusChip(label: chip.label, tone: chip.tone),
      ],
    );
  }
}
