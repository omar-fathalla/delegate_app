import 'dart:async';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/core/utils/promo_clock_binding.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/data/repositories/subscription_renewal_repository.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:delegate_app/features/admin/domain/services/subscription_payment_gateway.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/features/admin/presentation/pages/subscription_renewal_receipt_page.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

/// «تجديد المناديب»: supervisors, company admins, HR, and org-admins
/// (with a companyUID) may create a renewal (Phase 1 item 2).
///
/// Lists the company's app-added delegates, with filters for suspended and
/// nearly-ending subscriptions, auto-excludes already covered rows, and
/// pays for the selection in ONE Paymob payment after a confirmation sheet.
/// Coverage is recorded by the server; an advance payment does not
/// reactivate early. Selection/total logic lives in [RenewalSelection] and the
/// write in [SubscriptionRenewalRepository], so a per-row "renew" button can
/// reuse them later with `RenewalSelection.single(uid)`.
class SubscriptionRenewalScreen extends StatefulWidget {
  final Delegate supervisor;
  final SubscriptionRenewalRepository? repository;
  final SubscriptionPaymentGateway? paymentGateway;
  final DateTime Function()? clock;

  /// Inside the HR web shell the top bar already shows the title, so the
  /// screen swaps its AppBar for a slim toolbar with the same actions
  /// (TAS-143).
  final bool showAppBar;

  const SubscriptionRenewalScreen({
    super.key,
    required this.supervisor,
    this.repository,
    this.paymentGateway,
    this.clock,
    this.showAppBar = true,
  });

  static const String title = 'تجديد المناديب';

  @override
  State<SubscriptionRenewalScreen> createState() =>
      _SubscriptionRenewalScreenState();
}

class _SubscriptionRenewalScreenState extends State<SubscriptionRenewalScreen>
    with WidgetsBindingObserver, PromoClockBinding {
  late final SubscriptionRenewalRepository _repo =
      widget.repository ?? sl<SubscriptionRenewalRepository>();
  late final SubscriptionPaymentGateway _gateway =
      widget.paymentGateway ?? sl<SubscriptionPaymentGateway>();

  List<RenewableDelegate> _delegates = const [];
  RenewalSelection _selection = const RenewalSelection();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  RenewalListFilter _filter = RenewalListFilter.all;
  String? _activeRequestId;
  SubscriptionPaymentStatus? _activeStatus;
  StreamSubscription<SubscriptionPaymentStatus>? _statusSub;

  DateTime get _now =>
      (widget.clock ?? () => SubscriptionCycleHelper.currentTime())();

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
    final selectedPeriod = _selectedPeriod(_repo.currentPeriodCode(_now));
    final preview = await _gateway.previewQuote(
      companyUID: widget.supervisor.companyUID,
      organizationUID: widget.supervisor.organizationUID,
      uids: chosen.map((d) => d.uid).toList(),
      periodCode: selectedPeriod,
    );
    if (!mounted) return;
    RenewalQuotePreview? quoted;
    preview.fold(
      (f) {
        setState(() => _submitting = false);
        AppSnackBar.showError(context, f.message);
      },
      (q) {
        setState(() => _submitting = false);
        quoted = q;
      },
    );
    if (quoted == null) return;
    final fee = quoted!.feePerDelegate;
    final total = quoted!.amount;
    final period = quoted!.periodCode.isNotEmpty
        ? quoted!.periodCode
        : _selectedPeriod(_repo.currentPeriodCode(_now));
    final periodTitle = period.isEmpty
        ? ''
        : SubscriptionCycleHelper.getCycleTitleArabic(
            SubscriptionCycleHelper.getCycleStartDateForCode(period),
          );
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              key: const Key('renewal_confirm_sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ملخص التجديد قبل الدفع',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('الفترة: $periodTitle'),
                Text(
                  'عدد المناديب: ${chosen.length} × ${SubscriptionCycleHelper.formatEgp(fee)} ج.م = ${SubscriptionCycleHelper.formatEgp(total)} ج.م',
                  key: const Key('renewal_confirm_summary'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'دفعة واحدة عبر Paymob (بيئة الاختبار). المبلغ يحسبه الخادم، ولن يُجدَّد أي مندوب إن فشل الدفع.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('renewal_confirm_pay'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('تأكيد الدفع'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
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
        _openReceipt(requestId);
      } else if (changed && status == SubscriptionPaymentStatus.failed) {
        AppSnackBar.showError(
          context,
          'فشل الدفع (رفض البطاقة أو 3D Secure أو إلغاء العملية)، ولم يتم تفعيل أي مندوب. يمكنك إعادة المحاولة على نفس الطلب.',
        );
      } else if (changed && status == SubscriptionPaymentStatus.expired) {
        AppSnackBar.showError(
          context,
          'انتهت مهلة الدفع وتم إطلاق المناديب. يمكنك إعادة المحاولة على نفس الطلب أو إنشاء طلب جديد.',
        );
      }
    });
  }

  Future<void> _cancelPending(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const Key('renewal_cancel_confirm'),
          title: const Text('إلغاء طلب التجديد؟'),
          content: const Text(
            'سيتم إطلاق المناديب المحددين في هذا الطلب ويمكنك بدء طلب جديد.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع'),
            ),
            FilledButton(
              key: const Key('renewal_cancel_confirm_yes'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد الإلغاء'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final r = await _repo.cancelRenewal(requestId);
    if (!mounted) return;
    r.fold((f) => AppSnackBar.showError(context, f.message), (_) {
      if (_activeRequestId == requestId) {
        _statusSub?.cancel();
        setState(() {
          _activeRequestId = null;
          _activeStatus = null;
        });
      }
      _load();
    });
  }

  Future<void> _retryActiveCheckout() async {
    final id = _activeRequestId;
    if (id == null || _submitting) return;
    setState(() => _submitting = true);
    final checkout = await _gateway.startCheckout(requestId: id);
    if (!mounted) return;
    setState(() => _submitting = false);
    await checkout.fold(
      (f) async => AppSnackBar.showError(context, f.message),
      (c) async =>
          launchUrl(c.checkoutUrl, mode: LaunchMode.externalApplication),
    );
  }

  Future<void> _openReceipt(String requestId) async {
    final result = await _repo.loadReceipt(requestId);
    if (!mounted) return;
    result.fold((f) => AppSnackBar.showError(context, f.message), (receipt) {
      if (receipt == null) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubscriptionRenewalReceiptPage(receipt: receipt),
        ),
      );
    });
  }

  Future<void> _openPaidReceipts() async {
    final s = widget.supervisor;
    final result = await _repo.loadPaidRenewals(
      companyUID: s.companyUID,
      organizationUID: s.role == UserRole.organizationAdmin
          ? s.organizationUID
          : null,
    );
    if (!mounted) return;
    result.fold((f) => AppSnackBar.showError(context, f.message), (list) {
      if (list.isEmpty) {
        AppSnackBar.showInfo(context, 'لا توجد إيصالات تجديد مدفوعة بعد.');
        return;
      }
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: ListView(
              key: const Key('renewal_receipts_sheet'),
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'إيصالات التجديد',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                for (final r in list)
                  ListTile(
                    title: Text(
                      '${r.periodCode} • ${SubscriptionCycleHelper.formatEgp(r.amount)} ج.م',
                    ),
                    subtitle: Text('${r.delegateCount} مناديب'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SubscriptionRenewalReceiptPage(receipt: r),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      );
    });
  }

  List<RenewableDelegate> _applyFilter(Iterable<RenewableDelegate> input) {
    final now = _now;
    final expiring = isRenewalExpiringSoon(now);
    switch (_filter) {
      case RenewalListFilter.suspended:
        return [
          for (final d in input)
            if (d.isSuspendedExpired || d.status == 'suspended') d,
        ];
      case RenewalListFilter.expiringSoon:
        return [
          for (final d in input)
            if (expiring &&
                (d.periodCode.isEmpty ||
                    d.periodCode == _repo.currentPeriodCode(now)) &&
                !d.isCovered)
              d,
        ];
      case RenewalListFilter.all:
        return input.toList();
    }
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
    final visible = _applyFilter(_delegates);
    final selectable = visible.where((d) => d.isSelectable).toList();
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
        appBar: widget.showAppBar
            ? AppBar(
                title: const Text(SubscriptionRenewalScreen.title),
                actions: [
                  IconButton(
                    tooltip: 'إيصالات التجديد',
                    key: const Key('renewal_receipts_button'),
                    icon: const Icon(Icons.receipt_long_rounded),
                    onPressed: _loading ? null : _openPaidReceipts,
                  ),
                  IconButton(
                    tooltip: 'تحديث',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _loading ? null : _load,
                  ),
                ],
              )
            : null,
        body: Column(
          children: [
            if (!widget.showAppBar)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('renewal_receipts_button'),
                      icon: const Icon(Icons.receipt_long_rounded, size: 18),
                      label: const Text('إيصالات التجديد'),
                      onPressed: _loading ? null : _openPaidReceipts,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'تحديث',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _loading ? null : _load,
                    ),
                  ],
                ),
              ),
            _PeriodBanner(
              now: now,
              isFree: isFree,
              advance: advance,
              periodCode: advance ? nextPeriod : currentPeriod,
            ),
            if (_activeRequestId != null && _activeStatus != null)
              _PaymentStatusBanner(
                status: _activeStatus!,
                onRetry:
                    (_activeStatus == SubscriptionPaymentStatus.failed ||
                        _activeStatus == SubscriptionPaymentStatus.expired)
                    ? _retryActiveCheckout
                    : null,
              ),
            if (!_loading && _error == null && _delegates.isNotEmpty)
              _FilterBar(
                value: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
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
                          if (periodSelectable.length >
                              SubscriptionCycleHelper.maxDelegatesPerRenewal) {
                            AppSnackBar.showError(
                              context,
                              'تم تحديد أول ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوب فقط (الحد الأقصى في طلب واحد).',
                            );
                          }
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
                    Text('تحديد الكل (${periodSelectable.length})'),
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
      final advanceOpen = _repo.isAdvanceRenewalOpen(_now);
      if (WebRuntimePolicy.isWeb) {
        return HrEmptyState(
          key: const Key('renewal_empty_state'),
          icon: Icons.event_available_rounded,
          // Wording approved 21 Nov 2026 (TAS-174).
          title: advanceOpen ? 'كل الاشتراكات سارية' : 'لا يوجد مندوب موقوف',
          message: advanceOpen
              ? 'أي مندوب يقترب اشتراكه من الانتهاء سيظهر هنا لتجديده.'
              : 'إذا انتهى اشتراك مندوب، سيظهر هنا لتجديده.',
        );
      }
      final empty = advanceOpen
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
    final visible = _applyFilter(_delegates);
    final currentRows = visible
        .where((d) => d.periodCode == current || d.periodCode.isEmpty)
        .toList();
    final nextRows = visible.where((d) => d.periodCode == next).toList();
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
    if (currentRows.isEmpty && nextRows.isEmpty && visible.isEmpty) {
      if (WebRuntimePolicy.isWeb) {
        return HrEmptyState(
          icon: Icons.filter_alt_off_rounded,
          title: 'لا توجد نتائج لهذا التصنيف',
          action: TextButton(
            onPressed: () => setState(() => _filter = RenewalListFilter.all),
            child: const Text('عرض كل المناديب'),
          ),
        );
      }
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'لا يوجد مناديب في هذا التصنيف.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (sections.isEmpty) {
      sections.add(('تجديد المناديب', visible));
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
    if (d.isCovered) {
      return ListTile(
        key: key,
        leading: Icon(Icons.check_circle_outline, color: cs.primary),
        title: Text(d.fullName),
        subtitle: Text(
          [
            if (subtitle.isNotEmpty) subtitle,
            d.exclusionReason ?? 'مغطى بالفعل لهذه الفترة',
          ].join('\n'),
        ),
        isThreeLine: subtitle.isNotEmpty,
      );
    }
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
                  'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوبًا في طلب واحد.',
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitle.isNotEmpty) Text(subtitle),
          if (d.isSuspendedExpired)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'موقوف لانتهاء الاشتراك',
                  style: TextStyle(color: cs.onTertiaryContainer, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
      isThreeLine: d.isSuspendedExpired && subtitle.isNotEmpty,
      secondary: d.isSuspendedExpired
          ? Icon(
              Symbols.person_off_rounded,
              color: cs.onSurfaceVariant,
              fill: 0,
            )
          : null,
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
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                iconAlignment: IconAlignment.start,
              ),
              onPressed: canPay ? _payForSelection : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.credit_card_rounded, size: 24, fill: 0),
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
    final short = SubscriptionCycleHelper.getCycleShortTitleArabicForCode(
      periodCode,
    );
    if (advance) {
      // The selected-period isFree flag is false during the advance window,
      // so use the live promo clock. Drop the 2026 sentence after expiry.
      final promoNote = SubscriptionCycleHelper.isFreePromotionActive(now)
          ? ' ولا تُطبَّق مجانية 2026 على تلك الدورة.'
          : '';
      final openFor = short.startsWith('ال')
          ? 'ل${short.substring(1)}'
          : 'ل$short';
      text =
          'التجديد المقدَّم مفتوح $openFor. الرسوم 500 ج.م للمندوب عن الدورة الكاملة.$promoNote '
          'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوبًا في طلب واحد.';
    } else if (isFree) {
      text = 'الاشتراك مجاني حتى 31/12/2026، لا حاجة للتجديد الآن.';
    } else {
      text =
          '$short • متبقٍ $months ${months == 1 ? 'شهر' : 'أشهر'}. '
          'الحد الأقصى ${SubscriptionCycleHelper.maxDelegatesPerRenewal} مندوبًا في طلب واحد. '
          'يمكنك تجديد بعض المناديب الآن والباقي لاحقاً.';
    }
    if (WebRuntimePolicy.isWeb) {
      // M3 tonal info banner: leading icon and body text that wraps
      // (TAS-143). Mobile keeps the compact card below.
      return Container(
        key: const Key('renewal_period_banner_web'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: cs.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      );
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
  final VoidCallback? onRetry;
  const _PaymentStatusBanner({required this.status, this.onRetry});

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
        'فشل الدفع (رفض البطاقة أو 3D Secure أو إلغاء العملية)، ولم يتم تفعيل أي مندوب.',
      ),
      SubscriptionPaymentStatus.expired => (
        Icons.timer_off_rounded,
        Colors.orange.shade800,
        'انتهت مهلة الدفع (60 دقيقة) وتم إطلاق المناديب. يمكنك إعادة المحاولة على نفس الطلب أو إنشاء طلب جديد.',
      ),
      _ => (
        Icons.hourglass_top_rounded,
        cs.tertiary,
        'بانتظار تأكيد الدفع من Paymob. إذا أغلقت صفحة الدفع يمكنك العودة لاحقاً؛ سيُلغى الطلب تلقائياً خلال 60 دقيقة إن لم يصل التأكيد.',
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
          if (onRetry != null)
            TextButton(
              key: const Key('renewal_retry_payment'),
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final RenewalListFilter value;
  final ValueChanged<RenewalListFilter> onChanged;
  const _FilterBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(RenewalListFilter f, String label, Key key) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: FilterChip(
          key: key,
          label: Text(label),
          selected: value == f,
          onSelected: (_) => onChanged(f),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          chip(RenewalListFilter.all, 'الكل', const Key('renewal_filter_all')),
          chip(
            RenewalListFilter.suspended,
            'الموقوفون',
            const Key('renewal_filter_suspended'),
          ),
          chip(
            RenewalListFilter.expiringSoon,
            'يقترب انتهاء اشتراكهم',
            const Key('renewal_filter_expiring'),
          ),
        ],
      ),
    );
  }
}
