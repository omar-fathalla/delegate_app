import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_catalog_screen.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_audit_tile.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_capture_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_kpi_card.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_month_calendar.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_photo_pair.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_rest_day_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_access_denied_view.dart';

/// Fathalla Private Label — marketer page (daily documentation + monthly KPI).
class PrivateLabelScreen extends StatelessWidget {
  final Delegate delegate;

  const PrivateLabelScreen({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    if (delegate.role == UserRole.superAdmin) {
      return _buildContent(context);
    }

    return StreamBuilder<PrivateLabelPermissions?>(
      stream: sl<PrivateLabelPermissionsRemoteDataSource>()
          .streamUserPermissions(delegate.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final perms = snapshot.data;
        if (perms != null && perms.canCapture) {
          return _buildContent(context);
        }
        return const PrivateLabelAccessDeniedView(
          title: 'Private Label',
          screenName: 'التوثيق الميداني للبرايفت ليبل',
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return BlocProvider<PrivateLabelBloc>(
      create: (_) => sl<PrivateLabelBloc>()
        ..add(PrivateLabelStarted(
          organizationUID: delegate.organizationUID,
          companyUID: delegate.companyUID,
          delegateUid: delegate.uid,
          delegateName: delegate.fullName,
        )),
      child: _PrivateLabelView(delegate: delegate),
    );
  }
}

class _PrivateLabelView extends StatelessWidget {
  final Delegate delegate;

  const _PrivateLabelView({required this.delegate});

  static const double _wideBreakpoint = 900;

  // ─────────────────────────── Actions ───────────────────────────

  Future<void> _startQuickFlow(BuildContext context) async {
    final bloc = context.read<PrivateLabelBloc>();
    final state = bloc.state;

    // 1) Product on the shelf.
    final productPath = await PrivateLabelCamera.capture();
    if (productPath == null || !context.mounted) return;

    // 2) Price tag — opens immediately (the form allows retaking / skipping).
    HapticFeedback.selectionClick();
    AppSnackBar.showInfo(context, 'تمام، دلوقتي صوّر بطاقة السعر');
    final pricePath = await PrivateLabelCamera.capture();
    if (!context.mounted) return;

    // 3) Confirm product + shelf price.
    final prefs = sl<BranchPreferenceService>();
    final favorites = prefs.getFavoriteBranches(delegate.uid);
    final branches = [
      ...favorites.where(state.branches.contains),
      ...state.branches.where((b) => !favorites.contains(b)),
    ];
    final active = prefs.getActiveBranch(delegate.uid);
    final lastBranch = state.pendingDrafts.isNotEmpty
        ? state.pendingDrafts.last.branchName
        : (state.selectedDateAudits.isNotEmpty ? state.selectedDateAudits.first.branchName : null);

    final recent = <String>{
      ...state.pendingDrafts.reversed.map((d) => d.productName),
      ...state.selectedDateAudits.map((a) => a.productName),
    }.take(8).toList();

    final activeProducts = state.products.where((p) => p.isActive).toList();
    final catalogProducts = activeProducts.isNotEmpty
        ? activeProducts
        : PrivateLabelProduct.defaultCatalog(delegate.organizationUID);

    final draft = await showPrivateLabelSheet<PrivateLabelAuditDraft>(
      context: context,
      heightFactor: 0.9,
      builder: (ctx, layout) => PrivateLabelCaptureSheet(
        layout: layout,
        initialProductPath: productPath,
        initialPricePath: pricePath,
        branches: branches,
        initialBranch: lastBranch ?? (active != null && branches.contains(active) ? active : null),
        products: catalogProducts,
        recentProductNames: recent,
        organizationUID: delegate.organizationUID,
        companyUID: delegate.companyUID,
        delegateUid: delegate.uid,
        delegateName: delegate.fullName,
        clock: bloc.clock,
      ),
    );
    if (draft != null) bloc.add(PrivateLabelAuditSubmitted(draft));
  }

  Future<void> _registerRest(BuildContext context, String date) async {
    final bloc = context.read<PrivateLabelBloc>();
    final kpi = bloc.state.kpi;
    if (kpi != null && kpi.remainingRestDays <= 0) {
      AppSnackBar.showError(context, 'رصيد الإجازات للشهر ده خلص (${kpi.restAllowance} أيام).');
      return;
    }
    final ok = await confirmPrivateLabelRestDay(
      context: context,
      date: date,
      remainingRestDays: kpi?.remainingRestDays ?? bloc.state.restAllowance,
      restAllowance: kpi?.restAllowance ?? bloc.state.restAllowance,
    );
    if (ok) bloc.add(PrivateLabelRestDayRequested(date));
  }

  Future<void> _cancelRest(BuildContext context, String date) async {
    final bloc = context.read<PrivateLabelBloc>();
    final kpi = bloc.state.kpi;
    final ok = await confirmPrivateLabelRestDay(
      context: context,
      date: date,
      remainingRestDays: kpi?.remainingRestDays ?? 0,
      restAllowance: kpi?.restAllowance ?? bloc.state.restAllowance,
      cancel: true,
    );
    if (ok) bloc.add(PrivateLabelRestDayCancelled(date));
  }

  void _showAudit(BuildContext context, PrivateLabelAudit audit) {
    showPrivateLabelSheet<void>(
      context: context,
      builder: (ctx, layout) => _AuditDetailsSheet(layout: layout, audit: audit),
    );
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BlocListener<PrivateLabelBloc, PrivateLabelState>(
      listenWhen: (p, c) => c.feedback != null && p.feedback?.id != c.feedback?.id,
      listener: (context, state) {
        final f = state.feedback!;
        switch (f.type) {
          case PrivateLabelFeedbackType.success:
            AppSnackBar.showSuccess(context, f.message);
          case PrivateLabelFeedbackType.info:
            AppSnackBar.showInfo(context, f.message);
          case PrivateLabelFeedbackType.error:
            AppSnackBar.showError(context, f.message);
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('Private Label'),
          centerTitle: false,
          actions: [
            BlocBuilder<PrivateLabelBloc, PrivateLabelState>(
              buildWhen: (p, c) =>
                  p.pendingDrafts.length != c.pendingDrafts.length || p.isSyncing != c.isSyncing,
              builder: (context, state) {
                final count = state.pendingDrafts.length;
                return IconButton(
                  tooltip: count == 0 ? 'كل التوثيقات مترفوعة' : 'رفع $count توثيق محفوظ على الجهاز',
                  onPressed: state.isSyncing || count == 0
                      ? null
                      : () => context.read<PrivateLabelBloc>().add(const PrivateLabelSyncRequested(manual: true)),
                  icon: state.isSyncing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Badge(
                          isLabelVisible: count > 0,
                          label: Text('$count'),
                          child: Icon(count > 0 ? Icons.cloud_upload_rounded : Icons.cloud_done_rounded),
                        ),
                );
              },
            ),
            IconButton(
              tooltip: PrivateLabelCatalogScreen.canEditCatalog(delegate)
                  ? 'الكتالوج (منتجات البرايفت ليبل)'
                  : 'Catalog',
              icon: const Icon(Icons.inventory_2_rounded),
              onPressed: () async {
                final bloc = context.read<PrivateLabelBloc>();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PrivateLabelCatalogScreen(delegate: delegate),
                  ),
                );
                if (context.mounted) {
                  bloc.add(const PrivateLabelRefreshRequested());
                }
              },
            ),
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => context.read<PrivateLabelBloc>().add(const PrivateLabelRefreshRequested()),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: BlocBuilder<PrivateLabelBloc, PrivateLabelState>(
          buildWhen: (p, c) => p.isSubmitting != c.isSubmitting || p.status != c.status,
          builder: (context, state) => FloatingActionButton.extended(
            heroTag: 'pl_quick_flow_fab',
            onPressed: state.isSubmitting ? null : () => _startQuickFlow(context),
            icon: state.isSubmitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.onPrimaryContainer),
                  )
                : const Icon(Icons.add_a_photo_rounded),
            label: const Text('فحص منتج جديد'),
          ),
        ),
        body: BlocBuilder<PrivateLabelBloc, PrivateLabelState>(
          builder: (context, state) {
            if (state.kpi == null && state.status == PrivateLabelStatus.failure) {
              return _ErrorView(
                message: state.errorMessage ?? 'حصل خطأ أثناء التحميل',
                onRetry: () => context.read<PrivateLabelBloc>().add(const PrivateLabelRefreshRequested()),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                final bloc = context.read<PrivateLabelBloc>()..add(const PrivateLabelRefreshRequested());
                await bloc.stream.firstWhere((s) => !s.isRefreshing).timeout(
                      const Duration(seconds: 20),
                      onTimeout: () => bloc.state,
                    );
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= _wideBreakpoint;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 5, child: _kpiCard(context, state)),
                                  const SizedBox(width: 16),
                                  Expanded(flex: 6, child: _calendar(context, state)),
                                ],
                              )
                            else ...[
                              _kpiCard(context, state),
                              const SizedBox(height: 16),
                              _calendar(context, state),
                            ],
                            const SizedBox(height: 20),
                            _SelectedDaySection(
                              state: state,
                              todayKey: context.read<PrivateLabelBloc>().todayKey,
                              onAuditTap: (a) => _showAudit(context, a),
                              onRegisterRest: (d) => _registerRest(context, d),
                              onCancelRest: (d) => _cancelRest(context, d),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _kpiCard(BuildContext context, PrivateLabelState state) {
    final today = context.read<PrivateLabelBloc>().todayKey;
    final kpi = state.kpi;
    final isCurrentMonth = kpi != null && kpi.todayStatus != PrivateLabelTodayStatus.outsideMonth;
    final isReadOnlyCatalog = !PrivateLabelCatalogScreen.canEditCatalog(delegate);
    return PrivateLabelKpiCard(
      kpi: kpi,
      isLoading: kpi == null,
      isSyncing: state.isSyncing,
      pendingCount: state.pendingDrafts.length,
      onOpenCatalog: () async {
        final bloc = context.read<PrivateLabelBloc>();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrivateLabelCatalogScreen(delegate: delegate),
          ),
        );
        if (context.mounted) {
          bloc.add(const PrivateLabelRefreshRequested());
        }
      },
      catalogButtonLabel: isReadOnlyCatalog
          ? 'Catalog'
          : 'الكتالوج (منتجات البرايفت ليبل)',
      onRegisterRestToday: isCurrentMonth && !state.isUpdatingRest ? () => _registerRest(context, today) : null,
      onCancelRestToday: isCurrentMonth && !state.isUpdatingRest ? () => _cancelRest(context, today) : null,
    );
  }

  Widget _calendar(BuildContext context, PrivateLabelState state) {
    final bloc = context.read<PrivateLabelBloc>();
    final now = bloc.clock();
    // Allow browsing back freely, and one month ahead (to plan rest days).
    final maxMonth = DateTime(now.year, now.month + 1);
    final canGoNext = DateTime(state.year, state.month).isBefore(maxMonth);
    return PrivateLabelMonthCalendar(
      year: state.year,
      month: state.month,
      days: state.days,
      today: now,
      selectedDate: state.selectedDate,
      onDaySelected: (d) => bloc.add(PrivateLabelDateSelected(d)),
      onPreviousMonth: () {
        final prev = DateTime(state.year, state.month - 1);
        bloc.add(PrivateLabelMonthChanged(year: prev.year, month: prev.month));
      },
      onNextMonth: canGoNext
          ? () {
              final next = DateTime(state.year, state.month + 1);
              bloc.add(PrivateLabelMonthChanged(year: next.year, month: next.month));
            }
          : null,
    );
  }
}

// ─────────────────────────── Selected day ───────────────────────────

class _SelectedDaySection extends StatelessWidget {
  final PrivateLabelState state;
  final String todayKey;
  final ValueChanged<PrivateLabelAudit> onAuditTap;
  final ValueChanged<String> onRegisterRest;
  final ValueChanged<String> onCancelRest;

  const _SelectedDaySection({
    required this.state,
    required this.todayKey,
    required this.onAuditTap,
    required this.onRegisterRest,
    required this.onCancelRest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final date = state.selectedDate ?? todayKey;
    final day = state.dayFor(date);
    final drafts = state.pendingFor(date);
    final audits = state.selectedDateAudits;
    final isFutureOrToday = date.compareTo(todayKey) >= 0;
    final isRest = day?.isRest ?? false;
    final hasWork = drafts.isNotEmpty || audits.isNotEmpty || (day?.auditsCount ?? 0) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.event_note_rounded, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date == todayKey ? 'توثيقات اليوم • ${PrivateLabelLabels.dayTitle(date)}' : PrivateLabelLabels.dayTitle(date),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
            ),
            if (isRest)
              PrivateLabelStatusPill(icon: Icons.beach_access_rounded, label: 'إجازة', color: cs.secondary)
            else if (hasWork)
              PrivateLabelStatusPill(
                icon: Icons.check_circle_rounded,
                label: '${(day?.auditsCount ?? 0) + (day == null ? drafts.length : 0)} توثيق',
                color: cs.primary,
              ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: AppMotionDurations.medium2,
          reverseDuration: AppMotionDurations.short3,
          switchInCurve: AppMotionCurves.standardDecelerate,
          switchOutCurve: AppMotionCurves.standardAccelerate,
          child: KeyedSubtree(
            key: ValueKey('$date-${audits.length}-${drafts.length}-${state.isLoadingAudits}-$isRest'),
            child: _content(context, date, drafts, audits, isRest, hasWork, isFutureOrToday),
          ),
        ),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    String date,
    List<PrivateLabelAuditDraft> drafts,
    List<PrivateLabelAudit> audits,
    bool isRest,
    bool hasWork,
    bool isFutureOrToday,
  ) {
    final cs = Theme.of(context).colorScheme;

    if (state.isLoadingAudits && audits.isEmpty && drafts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (isRest) {
      return _EmptyState(
        icon: Icons.beach_access_rounded,
        title: 'اليوم ده مسجل كإجازة أسبوعية',
        subtitle: 'بيتحسب مكتمل 100% في نسبة الشهر.',
        action: isFutureOrToday
            ? OutlinedButton.icon(
                onPressed: state.isUpdatingRest ? null : () => onCancelRest(date),
                icon: const Icon(Icons.event_busy_rounded),
                label: const Text('إلغاء الإجازة'),
              )
            : null,
      );
    }

    if (!hasWork) {
      final isFuture = date.compareTo(todayKey) > 0;
      return _EmptyState(
        icon: isFuture ? Icons.event_rounded : Icons.photo_camera_back_rounded,
        title: isFuture
            ? 'يوم لسه مجاش'
            : (date == todayKey ? 'لسه مرفعتش صور النهارده ⏳' : 'مفيش توثيق في اليوم ده'),
        subtitle: isFuture
            ? 'تقدر تسجله إجازة من دلوقتي لو هتاخده.'
            : (date == todayKey ? 'اضغط «فحص منتج جديد» وصوّر المنتج وبطاقة السعر.' : 'اليوم ده محسوب فائت.'),
        action: isFutureOrToday
            ? OutlinedButton.icon(
                onPressed: state.isUpdatingRest ? null : () => onRegisterRest(date),
                icon: const Icon(Icons.beach_access_rounded),
                label: const Text('تسجيل كإجازة'),
              )
            : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (drafts.isNotEmpty) ...[
          PrivateLabelAccentContainer(
            accent: cs.tertiary,
            child: Row(
              children: [
                Icon(Icons.save_rounded, size: 18, color: cs.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم التوثيق محلياً — ${drafts.length} توثيق هيترفع تلقائياً أول ما النت يرجع.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final d in drafts.reversed) ...[
            PrivateLabelDraftTile(draft: d),
            const SizedBox(height: 8),
          ],
        ],
        for (final a in audits) ...[
          PrivateLabelAuditTile(audit: a, onTap: () => onAuditTap(a)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _EmptyState({required this.icon, required this.title, required this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: cs.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Audit details (read-only) ───────────────────────────

class _AuditDetailsSheet extends StatelessWidget {
  final PrivateLabelSheetLayout layout;
  final PrivateLabelAudit audit;

  const _AuditDetailsSheet({required this.layout, required this.audit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = PrivateLabelLabels.reviewColor(audit.reviewStatus, cs);

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
              ),
            ],
          ),
        );

    return PrivateLabelSheetFrame(
      layout: layout,
      icon: Icons.sell_rounded,
      title: audit.productName,
      subtitle: '${audit.branchName} • ${PrivateLabelLabels.time(audit.capturedAt)}',
      headerTrailing: PrivateLabelStatusPill(
        icon: PrivateLabelLabels.reviewIcon(audit.reviewStatus),
        label: PrivateLabelLabels.review(audit.reviewStatus),
        color: statusColor,
      ),
      actions: PrivateLabelConnectedActions(
        secondaryLabel: 'رجوع',
        secondaryIcon: Icons.arrow_forward_rounded,
        primaryLabel: 'تمام',
        primaryIcon: Icons.check_rounded,
        onPrimary: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          PrivateLabelPhotoPair(productPhoto: audit.productPhotoUrl, pricePhoto: audit.pricePhotoUrl, height: 200),
          const SizedBox(height: 12),
          row(Icons.payments_rounded, 'سعر الرف', PrivateLabelLabels.price(audit.shelfPrice)),
          if (audit.referencePrice != null)
            row(Icons.verified_rounded, 'السعر المعتمد', PrivateLabelLabels.price(audit.referencePrice!)),
          row(PrivateLabelLabels.stockIcon(audit.stockStatus), 'حالة المنتج', PrivateLabelLabels.stock(audit.stockStatus)),
          if (audit.notes != null && audit.notes!.isNotEmpty) row(Icons.sticky_note_2_rounded, 'ملاحظاتك', audit.notes!),
          if (audit.reviewStatus != PrivateLabelReviewStatus.pending) ...[
            const SizedBox(height: 10),
            PrivateLabelAccentContainer(
              accent: statusColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'قرار المراجعة: ${PrivateLabelLabels.review(audit.reviewStatus)}'
                    '${audit.reviewedByName != null ? ' • ${audit.reviewedByName}' : ''}',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
                  ),
                  if (audit.reviewNotes != null && audit.reviewNotes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(audit.reviewNotes!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface)),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
