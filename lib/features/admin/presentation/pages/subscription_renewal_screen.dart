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

/// «تجديد المناديب»: company admin or HR renewal page (Mohamed policy #212).
///
/// Lists his company's suspended (subscription expired) app-added delegates,
/// lets him select any subset, and pays for the selection in ONE Paymob
/// payment. Only delegates in a verified, paid renewal are reactivated (by
/// the server). Selection/total logic lives in [RenewalSelection] and the
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
  State<SubscriptionRenewalScreen> createState() => _SubscriptionRenewalScreenState();
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
    final result = await _repo.loadRenewableDelegates(widget.supervisor.companyUID);
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
    final chosen = _delegates.where((d) => _selection.isSelected(d.uid)).toList();
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
          (c) async => launchUrl(c.checkoutUrl, mode: LaunchMode.externalApplication),
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
        AppSnackBar.showSuccess(context, 'تم تأكيد الدفع وإعادة تفعيل المناديب المحددين.');
        _load();
      } else if (changed && status == SubscriptionPaymentStatus.failed) {
        AppSnackBar.showError(context, 'فشل الدفع، ولم يتم تفعيل أي مندوب. يمكنك المحاولة مرة أخرى.');
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
    final isFree = SubscriptionCycleHelper.isFreePromotionActive(now);
    final selectable = _delegates.where((d) => !d.isAwaitingPayment).toList();
    final allSelected = selectable.isNotEmpty && _selection.count == selectable.length;

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
            _PeriodBanner(now: now, isFree: isFree),
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
                      onChanged: (v) => setState(() => _selection =
                          v == true ? _selection.selectAll(_delegates) : _selection.clear()),
                    ),
                    Text('تحديد الكل (${selectable.length})'),
                  ],
                ),
              ),
            Expanded(child: _buildList(cs)),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(cs, now, isFree),
      ),
    );
  }

  Widget _buildList(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
        ),
      );
    }
    if (_delegates.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا يوجد مناديب موقوفون بانتهاء الاشتراك حالياً.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _delegates.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final d = _delegates[i];
        final subtitle = [
          if (d.organizationName.isNotEmpty) d.organizationName,
          if (d.phoneNumber.isNotEmpty) d.phoneNumber,
          if (d.delegatePublicId?.isNotEmpty == true) d.delegatePublicId!,
        ].join(' • ');
        if (d.isAwaitingPayment) {
          return ListTile(
            key: Key('renewal_row_${d.uid}'),
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
          key: Key('renewal_row_${d.uid}'),
          value: _selection.isSelected(d.uid),
          onChanged: _submitting
              ? null
              : (_) {
                  final wasSelected = _selection.isSelected(d.uid);
                  final next = _selection.toggle(d.uid);
                  if (!wasSelected &&
                      next.count == _selection.count &&
                      _selection.count >= SubscriptionCycleHelper.maxDelegatesPerRenewal) {
                    AppSnackBar.showError(
                      context,
                      'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوباً في طلب تجديد واحد.',
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
      },
    );
  }

  Widget? _buildBottomBar(ColorScheme cs, DateTime now, bool isFree) {
    if (_loading || _delegates.isEmpty) return null;
    final fee = _selection.feePerDelegate(now);
    final total = _selection.total(now);
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.primary),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              key: const Key('renewal_pay_button'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: canPay ? _payForSelection : null,
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
  const _PeriodBanner({required this.now, required this.isFree});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final months = SubscriptionCycleHelper.getRemainingMonthsInCycle(now);
    final text = isFree
        ? 'الاشتراك مجاني حتى 31/12/2026، لا حاجة للتجديد الآن.'
        : '${SubscriptionCycleHelper.getCycleTitleArabic(now)} • متبقٍ $months ${months == 1 ? 'شهر' : 'أشهر'}. '
            'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوباً في طلب واحد. '
            'يمكنك تجديد بعض المناديب الآن والباقي لاحقاً.';
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
      SubscriptionPaymentStatus.paid => (Icons.check_circle_rounded, cs.primary, 'تم الدفع وتفعيل المناديب المحددين.'),
      SubscriptionPaymentStatus.failed => (Icons.error_rounded, cs.error, 'فشل الدفع، ولم يتم تفعيل أي مندوب.'),
      _ => (Icons.hourglass_top_rounded, cs.tertiary, 'طلب التجديد بانتظار تأكيد الدفع من Paymob.'),
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
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
      ]),
    );
  }
}
