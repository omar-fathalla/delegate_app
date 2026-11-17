import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/data/company_chains.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// «طلبات ضم سلاسل» on the web requests page: company-level requests (no
/// delegate on them). Super admin / technical support see all; a chain
/// admin sees only their own chain. Approving registers the company in the
/// chain; the Cloud Function then links the company's active, paid
/// delegates. Old delegate requests keep their own list below.
class CompanyChainRequestsPanel extends StatefulWidget {
  const CompanyChainRequestsPanel({
    super.key,
    required this.reviewer,
    this.requestsOverride,
    this.firestore,
  });

  final Delegate reviewer;

  /// Fake data for tests / screenshots.
  final List<CompanyChainRequest>? requestsOverride;
  final FirebaseFirestore? firestore;

  static const panelKey = Key('company_chain_requests_panel');
  static Key approveKey(String id) => Key('company_chain_approve_$id');
  static Key rejectKey(String id) => Key('company_chain_reject_$id');

  @override
  State<CompanyChainRequestsPanel> createState() => _CompanyChainRequestsPanelState();
}

class _CompanyChainRequestsPanelState extends State<CompanyChainRequestsPanel> {
  Stream<List<CompanyChainRequest>>? _stream;
  final Set<String> _busy = {};
  bool _expanded = true;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    if (widget.requestsOverride == null && canReviewCompanyChainRequests(widget.reviewer)) {
      _stream = watchPendingCompanyChainRequests(firestore: _db, reviewer: widget.reviewer);
    }
  }

  Future<void> _decide(List<CompanyChainRequest> list, {required bool approve}) async {
    String reason = '';
    if (!approve) {
      final r = await _askReason();
      if (r == null) return;
      reason = r;
    }
    setState(() => _busy.addAll(list.map((r) => r.id)));
    var ok = 0;
    String? error;
    for (final r in list) {
      try {
        if (approve) {
          await approveCompanyChainRequest(firestore: _db, request: r, reviewer: widget.reviewer);
        } else {
          await rejectCompanyChainRequest(firestore: _db, request: r, reviewer: widget.reviewer, reason: reason);
        }
        ok++;
      } on StateError catch (e) {
        error = e.message;
      } catch (_) {
        error = 'تعذر تنفيذ القرار على بعض الطلبات. حاول مرة أخرى.';
      }
    }
    if (!mounted) return;
    setState(() => _busy.removeAll(list.map((r) => r.id)));
    if (error != null) {
      AppSnackBar.showError(context, error);
    } else {
      AppSnackBar.showSuccess(
        context,
        approve
            ? 'تمت الموافقة على $ok طلب ضم. فروع السلسلة ستظهر لمناديب الشركة النشطين المدفوع اشتراكهم.'
            : 'تم رفض $ok طلب ضم.',
      );
    }
  }

  Future<String?> _askReason() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سبب الرفض'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'اكتب السبب (اختياري)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('رفض')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requestsOverride != null) return _build(context, widget.requestsOverride!);
    final stream = _stream;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<CompanyChainRequest>>(
      stream: stream,
      builder: (context, snap) => _build(context, snap.data ?? const []),
    );
  }

  Widget _build(BuildContext context, List<CompanyChainRequest> all) {
    if (all.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final byCompany = <String, List<CompanyChainRequest>>{};
    for (final r in all) {
      byCompany.putIfAbsent(r.companyUID, () => []).add(r);
    }
    return Container(
      key: CompanyChainRequestsPanel.panelKey,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Icon(Symbols.add_business_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'طلبات ضم سلاسل (${all.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                  ),
                  Icon(_expanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final entry in byCompany.entries) _companyGroup(cs, entry.value),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _companyGroup(ColorScheme cs, List<CompanyChainRequest> list) {
    final first = list.first;
    final busy = list.any((r) => _busy.contains(r.id));
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Symbols.domain_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(first.companyName.isEmpty ? first.companyUID : first.companyName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      'طلب ضم ${list.length} سلسلة · ${first.supervisorName}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (list.length > 1)
                TextButton(
                  onPressed: busy ? null : () => _decide(list, approve: true),
                  child: const Text('موافقة على الكل'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const SizedBox(width: 26),
                  Expanded(
                    child: Text(r.organizationName, style: const TextStyle(fontSize: 13.5)),
                  ),
                  IconButton(
                    key: CompanyChainRequestsPanel.rejectKey(r.id),
                    tooltip: 'رفض',
                    onPressed: _busy.contains(r.id) ? null : () => _decide([r], approve: false),
                    icon: Icon(Symbols.close_rounded, color: cs.error),
                  ),
                  IconButton.filledTonal(
                    key: CompanyChainRequestsPanel.approveKey(r.id),
                    tooltip: 'موافقة',
                    onPressed: _busy.contains(r.id) ? null : () => _decide([r], approve: true),
                    icon: _busy.contains(r.id)
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Symbols.check_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
