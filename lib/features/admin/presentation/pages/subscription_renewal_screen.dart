import 'dart:async';

import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/data/repositories/subscription_renewal_repository.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:delegate_app/features/admin/domain/services/subscription_payment_gateway.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// «تجديد المناديب»: supervisors, company admins, HR, and org-admins
/// (with a companyUID) may create a renewal (Phase 1 item 2).
///
/// Lists his company's renewable app-added delegates, lets him select any
/// subset, and pays for the selection in ONE Paymob payment. During the
/// advance-renewal window the list is next-period coverage (including
/// currently active delegates); otherwise it is suspended-for-expiry only.
/// Coverage is recorded by the server; an advance payment does not
/// reactivate early. Selection/total logic lives in [RenewalSelection] and the
/// write in [SubscriptionRenewalRepository], so a per-row "renew" button can
/// reuse them later with `RenewalSelection.single(uid)`.
class SubscriptionRenewalScreen extends StatefulWidget {
  final Delegate supervisor;
  final SubscriptionRenewalRepository? repository;
  final SubscriptionPaymentGateway? paymentGateway;
  final DateTime Function()? clock;

  const SubscriptionRenewalScreen({
    super.key,
    required this.supervisor,
    this.repository,
    this.paymentGateway,
    this.clock,
  });

  static const String title = 'تجديد المناديب';

  @override
  State<SubscriptionRenewalScreen> createState() =>
      _SubscriptionRenewalScreenState();
}

class _SubscriptionRenewalScreenState extends State<SubscriptionRenewalScreen> {
  late final SubscriptionRenewalRepository _repo =
      widget.repository ?? sl<SubscriptionRenewalRepository>();
  late final SubscriptionPaymentGateway _gateway =
      widget.paymentGateway ?? sl<SubscriptionPaymentGateway>();

  List<RenewableDelegate> _delegates = const [];
  RenewalSelection _selection = const RenewalSelection();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _activeRequestId;
  SubscriptionPaymentStatus? _activeStatus;
  StreamSubscription<SubscriptionPaymentStatus>? _statusSub;

  DateTime get _now => (widget.clock ?? () => DateTime.now().toUtc())();

  String _selectedPeriod(String fallback) {
    final keys = _selection.selectedUids;
    if (keys.isEmpty) return fallback;
    final periods = _delegates
        .where((d) => _selection.isSelected(d.selectionKey))
        .map((d) => d.periodCode)
        .where((p) => p.isNotEmpty)
        .toSet();
    if (periods.length == 1) return periods.single;
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final supervisor = widget.supervisor;
    final result = await _repo.loadRenewableDelegates(
      companyUID: supervisor.companyUID,
      organizationUID: supervisor.role == UserRole.organizationAdmin
          ? supervisor.organizationUID
          : null,
    );
    if (!mounted) return;
    result.fold(
      (f) => setState(() {
        _loading = false;
        _error = f.message;
      }),
      (list) => setState(() {
        _loading = false;
        _delegates = list;
        _selection = _selection.retainOnly(list);
      }),
    );
  }

  Future<void> _payForSelection() async {
    final chosen = _delegates
        .where((d) => _selection.isSelected(d.selectionKey))
        .toList();
    if (chosen.isEmpty) return;
    setState(() => _submitting = true);
    final s = widget.supervisor;
    final created = await _repo.submitRenewal(
      supervisorUid: s.uid,
      supervisorName: s.fullName,
      supervisorPhone: s.phoneNumber,
      companyUID: s.companyUID,
      companyName: s.companyName,
      organizationUID: s.organizationUID,
      organizationName: s.organizationName,
      delegates: chosen,
    );
    if (!mounted) return;
    await created.fold(
      (f) async {
        setState(() => _submitting = false);
        AppSnackBar.showError(context, f.message);
      },
      (requestId) async {
        _watch(requestId);
        final checkout = await _gateway.startCheckout(requestId: requestId);
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _selection = _selection.clear();
        });
        await checkout.fold(
          (f) async => AppSnackBar.showError(context, f.message),
          (c) async =>
              launchUrl(c.checkoutUrl, mode: LaunchMode.externalApplication),
        );
        await _load();
      },
    );
  }

  void _watch(String requestId) {
    _statusSub?.cancel();
    setState(() {
      _activeRequestId = requestId;
      _activeStatus = SubscriptionPaymentStatus.pending;
    });
    _statusSub = _repo.watchPaymentStatus(requestId).listen((status) {
      if (!mounted) return;
      final changed = status != _activeStatus;
      setState(() => _activeStatus = status);
      if (changed && status == SubscriptionPaymentStatus.paid) {
        AppSnackBar.showSuccess(
          context,
          'تم تأكيد الدفع وتسجيل التغطية للمناديب المحددين.',
        );
        _load();
      } else if (changed && status == SubscriptionPaymentStatus.failed) {
        AppSnackBar.showError(
          context,
          'فشل الدفع، ولم يتم تفعيل أي مندوب. يمكنك المحاولة مرة أخرى.',
        );
      }
    });
  }

  Future<void> _cancelPending(String requestId) async {
    final r = await _repo.cancelRenewal(requestId);
    if (!mounted) return;
    r.fold((f) => AppSnackBar.showError(context, f.message), (_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = _now;
    final advance = _repo.isAdvanceRenewalOpen(now);
    final currentPeriod = _repo.currentPeriodCode(now);
    final nextPeriod = _repo.nextPeriodCode(now);
    final selectedPeriod = _selectedPeriod(currentPeriod);
    final isFree =
        selectedPeriod == currentPeriod &&
        SubscriptionCycleHelper.isFreePromotionActive(
          now,
          widget.supervisor.companyUID,
        );
    final selectable = _delegates.where((d) => !d.isAwaitingPayment).toList();
    final periodForSelectAll = _selectedPeriod(currentPeriod);
    final periodSelectable = selectable
        .where(
          (d) =>
              d.periodCode == periodForSelectAll ||
              (d.periodCode.isEmpty && periodForSelectAll == currentPeriod),
        )
        .toList();
    final allSelected =
        periodSelectable.isNotEmpty &&
        _selection.count == periodSelectable.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(SubscriptionRenewalScreen.title),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: Column(
          children: [
            _PeriodBanner(
              now: now,
              isFree: isFree,
              advance: advance,
              periodCode: advance ? nextPeriod : currentPeriod,
            ),
            if (_activeRequestId != null && _activeStatus != null)
              _PaymentStatusBanner(status: _activeStatus!),
            if (!_loading && _error == null && selectable.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Checkbox(
                      key: const Key('renewal_select_all'),
                      value: allSelected,
                      onChanged: (v) {
                        if (v == true) {
                          setState(
                            () => _selection = _selection.selectAll(
                              periodSelectable,
                            ),
                          );
                        } else {
                          setState(() => _selection = _selection.clear());
                        }
                      },
                    ),
                    Text('تحديد الكل (${selectable.length})'),
                  ],
                ),
              ),
            Expanded(child: _buildList(cs)),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(cs, now, isFree, selectedPeriod),
      ),
    );
  }

  Widget _buildList(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.error),
          ),
        ),
      );
    }
    if (_delegates.isEmpty) {
      final empty = _repo.isAdvanceRenewalOpen(_now)
          ? 'لا يوجد مناديب بحاجة للتجديد في الفترة الحالية أو التجديد المقدَّم حالياً.'
          : 'لا يوجد مناديب موقوفون بانتهاء الاشتراك حالياً.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(empty, textAlign: TextAlign.center),
        ),
      );
    }
    final now = _now;
    final current = _repo.currentPeriodCode(now);
    final next = _repo.nextPeriodCode(now);
    final currentRows = _delegates
        .where((d) => d.periodCode == current || d.periodCode.isEmpty)
        .toList();
    final nextRows = _delegates.where((d) => d.periodCode == next).toList();
    final sections = <(String, List<RenewableDelegate>)>[
      if (currentRows.isNotEmpty)
        (
          'الفترة الحالية • ${SubscriptionCycleHelper.getCycleTitleArabic(now)}',
          currentRows,
        ),
      if (nextRows.isNotEmpty)
        (
          'التجديد المقدَّم • ${SubscriptionCycleHelper.getCycleTitleArabic(SubscriptionCycleHelper.getCycleStartDateForCode(next))}',
          nextRows,
        ),
    ];
    if (sections.isEmpty) {
      sections.add(('تجديد المناديب', _delegates));
    }

    final children = <Widget>[];
    for (final (title, rows) in sections) {
      if (_repo.isAdvanceRenewalOpen(now) || sections.length > 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
            ),
          ),
        );
      }
      for (final d in rows) {
        children.add(_buildRow(cs, d));
        children.add(const Divider(height: 1));
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildRow(ColorScheme cs, RenewableDelegate d) {
    final subtitle = [
      if (d.organizationName.isNotEmpty) d.organizationName,
      if (d.phoneNumber.isNotEmpty) d.phoneNumber,
      if (d.delegatePublicId?.isNotEmpty == true) d.delegatePublicId!,
    ].join(' • ');
    final key = Key('renewal_row_${d.selectionKey}');
    if (d.isAwaitingPayment) {
      return ListTile(
        key: key,
        leading: const Icon(Icons.hourglass_top_rounded),
        title: Text(d.fullName),
        subtitle: Text('$subtitle\nبانتظار الدفع في طلب تجديد سابق'),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: () => _cancelPending(d.pendingRenewalRequestId!),
          child: const Text('إلغاء الطلب'),
        ),
      );
    }
    return CheckboxListTile(
      key: key,
      value: _selection.isSelected(d.selectionKey),
      onChanged: _submitting
          ? null
          : (_) {
              final wasSelected = _selection.isSelected(d.selectionKey);
              final next = _selection.toggle(d.selectionKey);
              if (!wasSelected &&
                  next.count == _selection.count &&
                  _selection.count >=
                      SubscriptionCycleHelper.maxDelegatesPerRenewal) {
                AppSnackBar.showError(
                  context,
                  'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوباً في طلب واحد.',
                );
                return;
              }
              // Keep a selection inside one period.
              final mixed = _delegates
                  .where((row) => next.isSelected(row.selectionKey))
                  .map((row) => row.periodCode)
                  .where((p) => p.isNotEmpty)
                  .toSet();
              if (mixed.length > 1) {
                AppSnackBar.showError(
                  context,
                  'لا يمكن جمع تجديد الفترة الحالية والتجديد المقدَّم في طلب واحد.',
                );
                return;
              }
              setState(() => _selection = next);
            },
      title: Text(d.fullName),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      secondary: Icon(Icons.person_off_rounded, color: cs.error),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget? _buildBottomBar(
    ColorScheme cs,
    DateTime now,
    bool isFree,
    String selectedPeriod,
  ) {
    if (_loading || _delegates.isEmpty) return null;
    final period = selectedPeriod.isEmpty ? null : selectedPeriod;
    final fee = _selection.feePerDelegate(
      now,
      widget.supervisor.companyUID,
      period,
    );
    final total = _selection.total(now, widget.supervisor.companyUID, period);
    final canPay = !_submitting && !isFree && !_selection.isEmpty;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المحدد: ${_selection.count} • ${SubscriptionCycleHelper.formatEgp(fee)} ج.م للمندوب',
                    key: const Key('renewal_selected_count'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  Text(
                    'الإجمالي: ${SubscriptionCycleHelper.formatEgp(total)} ج.م',
                    key: const Key('renewal_total'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              key: const Key('renewal_pay_button'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: canPay ? _payForSelection : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.credit_card_rounded, size: 18),
              label: const Text('ادفع عبر Paymob'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodBanner extends StatelessWidget {
  final DateTime now;
  final bool isFree;
  final bool advance;
  final String periodCode;
  const _PeriodBanner({
    required this.now,
    required this.isFree,
    required this.advance,
    required this.periodCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final months = SubscriptionCycleHelper.getRemainingMonthsInCycle(now);
    final String text;
    if (advance) {
      final title = SubscriptionCycleHelper.getCycleTitleArabic(
        SubscriptionCycleHelper.getCycleStartDateForCode(periodCode),
      );
      text =
          'التجديد المقدَّم مفتوح ل$title. الرسوم كاملة للدورة التالية، '
          'ولا تُطبَّق مجانية 2026 على تلك الدورة. '
          'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوباً في طلب واحد.';
    } else if (isFree) {
      text = 'الاشتراك مجاني حتى 31/12/2026، لا حاجة للتجديد الآن.';
    } else {
      text =
          '${SubscriptionCycleHelper.getCycleTitleArabic(now)} • متبقٍ $months ${months == 1 ? 'شهر' : 'أشهر'}. '
          'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوباً في طلب واحد. '
          'يمكنك تجديد بعض المناديب الآن والباقي لاحقاً.';
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.5)),
    );
  }
}

class _PaymentStatusBanner extends StatelessWidget {
  final SubscriptionPaymentStatus status;
  const _PaymentStatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (status) {
      SubscriptionPaymentStatus.paid => (
        Icons.check_circle_rounded,
        cs.primary,
        'تم الدفع وتسجيل التغطية للمناديب المحددين.',
      ),
      SubscriptionPaymentStatus.failed => (
        Icons.error_rounded,
        cs.error,
        'فشل الدفع، ولم يتم تفعيل أي مندوب.',
      ),
      SubscriptionPaymentStatus.expired => (
        Icons.timer_off_rounded,
        Colors.orange.shade800,
        'انتهت صلاحية عرض السعر. يمكن إنشاء طلب تجديد جديد.',
      ),
      _ => (
        Icons.hourglass_top_rounded,
        cs.tertiary,
        'طلب التجديد بانتظار تأكيد الدفع من Paymob.',
      ),
    };
    return Container(
      key: const Key('renewal_payment_status'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}
