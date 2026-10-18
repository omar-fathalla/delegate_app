import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_review_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_catalog_screen.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_audit_edit_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_audit_tile.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_photo_pair.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_review_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_access_denied_view.dart';

/// Marketing Promotion (audit): daily triage & approvals of Private Label documentation.
class PrivateLabelReviewScreen extends StatelessWidget {
  final Delegate delegate;

  const PrivateLabelReviewScreen({super.key, required this.delegate});

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
        if (perms != null && perms.canReviewAudit) {
          return _buildContent(context);
        }
        return const PrivateLabelAccessDeniedView(
          title: 'اعتمادات Private Label',
          screenName: 'مراجعة وتدقيق واعتماد البرايفت ليبل',
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return BlocProvider<PrivateLabelReviewBloc>(
      create: (_) => sl<PrivateLabelReviewBloc>()
        ..add(PrivateLabelReviewStarted(
          organizationUID: delegate.organizationUID,
          companyUID: delegate.companyUID,
          reviewerUid: delegate.uid,
          reviewerName: delegate.fullName,
        )),
      child: _ReviewView(delegate: delegate),
    );
  }
}

class _ReviewView extends StatelessWidget {
  final Delegate delegate;

  const _ReviewView({required this.delegate});

  Future<void> _handleEdit(BuildContext context, PrivateLabelAudit audit, List<PrivateLabelProduct> products) async {
    final bloc = context.read<PrivateLabelReviewBloc>();
    final updated = await showPrivateLabelAuditEditSheet(
      context: context,
      audit: audit,
      products: products,
    );
    if (updated != null) {
      bloc.add(PrivateLabelReviewAuditUpdated(updated));
    }
  }

  Future<void> _handleDelete(BuildContext context, PrivateLabelAudit audit) async {
    final bloc = context.read<PrivateLabelReviewBloc>();
    final confirmed = await confirmPrivateLabelAuditDeletion(
      context: context,
      audit: audit,
    );
    if (confirmed) {
      bloc.add(PrivateLabelReviewAuditDeleted(audit));
    }
  }

  Future<void> _openAudit(BuildContext context, PrivateLabelAudit audit, List<PrivateLabelProduct> products) async {
    final bloc = context.read<PrivateLabelReviewBloc>();
    final decision = await showPrivateLabelReviewSheet(
      context: context,
      audit: audit,
      products: products,
      onEdit: (updated) => bloc.add(PrivateLabelReviewAuditUpdated(updated)),
      onDelete: () => bloc.add(PrivateLabelReviewAuditDeleted(audit)),
    );
    if (decision == null) return;
    bloc.add(PrivateLabelReviewDecisionSubmitted(
      auditId: audit.id,
      status: decision.status,
      notes: decision.notes,
    ));
  }

  Future<void> _showDateFilterSheet(BuildContext context, String? currentDate) async {
    final bloc = context.read<PrivateLabelReviewBloc>();
    final now = DateTime.now();
    final todayKey = PrivateLabelDates.dayKey(now);
    final yesterdayKey = PrivateLabelDates.dayKey(now.subtract(const Duration(days: 1)));

    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width > 768;

    Widget buildSheetContent(BuildContext ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isDesktop)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Text(
                  'فلترة التوثيقات بالتاريخ',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.all_inclusive_rounded,
              color: currentDate == null ? cs.primary : cs.onSurfaceVariant,
            ),
            title: const Text('جميع التواريخ (قائمة الانتظار الكاملة)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('عرض كافة التوثيقات دون التقيد بيوم محدد'),
            trailing: currentDate == null ? Icon(Icons.check_rounded, color: cs.primary) : null,
            onTap: () {
              Navigator.of(ctx).pop();
              bloc.add(const PrivateLabelReviewDateChanged(null));
            },
          ),
          ListTile(
            leading: Icon(
              Icons.today_rounded,
              color: currentDate == todayKey ? cs.primary : cs.onSurfaceVariant,
            ),
            title: const Text('توثيقات اليوم (النهارده)'),
            subtitle: Text(todayKey),
            trailing: currentDate == todayKey ? Icon(Icons.check_rounded, color: cs.primary) : null,
            onTap: () {
              Navigator.of(ctx).pop();
              bloc.add(PrivateLabelReviewDateChanged(todayKey));
            },
          ),
          ListTile(
            leading: Icon(
              Icons.history_rounded,
              color: currentDate == yesterdayKey ? cs.primary : cs.onSurfaceVariant,
            ),
            title: const Text('توثيقات أمس'),
            subtitle: Text(yesterdayKey),
            trailing: currentDate == yesterdayKey ? Icon(Icons.check_rounded, color: cs.primary) : null,
            onTap: () {
              Navigator.of(ctx).pop();
              bloc.add(PrivateLabelReviewDateChanged(yesterdayKey));
            },
          ),
          ListTile(
            leading: Icon(Icons.date_range_rounded, color: cs.onSurfaceVariant),
            title: const Text('اختيار تاريخ مخصص من التقويم...'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () async {
              Navigator.of(ctx).pop();
              final initial = currentDate != null ? PrivateLabelDates.parseDayKey(currentDate) : now;
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(now.year - 1),
                lastDate: now,
              );
              if (picked != null) {
                bloc.add(PrivateLabelReviewDateChanged(PrivateLabelDates.dayKey(picked)));
              }
            },
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    if (isDesktop) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: buildSheetContent(ctx),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: buildSheetContent(ctx),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BlocListener<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      listenWhen: (p, c) => c.feedback != null && p.feedback?.id != c.feedback?.id,
      listener: (context, state) {
        final f = state.feedback!;
        f.isError ? AppSnackBar.showError(context, f.message) : AppSnackBar.showSuccess(context, f.message);
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: BlocBuilder<PrivateLabelReviewBloc, PrivateLabelReviewState>(
            buildWhen: (p, c) => p.date != c.date,
            builder: (context, state) {
              final subtitle = state.date == null
                  ? 'جميع التواريخ (قائمة الانتظار)'
                  : PrivateLabelLabels.dayTitle(state.date!);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Private Label Audit'),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                  ),
                ],
              );
            },
          ),
          centerTitle: false,
          actions: [
            BlocBuilder<PrivateLabelReviewBloc, PrivateLabelReviewState>(
              buildWhen: (p, c) => p.date != c.date,
              builder: (context, state) {
                final hasDate = state.date != null;
                return IconButton(
                  tooltip: hasDate
                      ? 'تاريخ محدد: ${PrivateLabelLabels.dayTitle(state.date!)}'
                      : 'فلترة بالتاريخ',
                  icon: Badge(
                    isLabelVisible: hasDate,
                    smallSize: 8,
                    backgroundColor: cs.primary,
                    child: Icon(
                      Icons.calendar_month_rounded,
                      color: hasDate ? cs.primary : null,
                    ),
                  ),
                  onPressed: () => _showDateFilterSheet(context, state.date),
                );
              },
            ),
            IconButton(
              tooltip: 'الكتالوج (منتجات البرايفت ليبل)',
              icon: const Icon(Icons.inventory_2_rounded),
              onPressed: () async {
                final bloc = context.read<PrivateLabelReviewBloc>();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PrivateLabelCatalogScreen(delegate: delegate),
                  ),
                );
                if (context.mounted) {
                  bloc.add(const PrivateLabelReviewRefreshRequested());
                }
              },
            ),
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () =>
                  context.read<PrivateLabelReviewBloc>().add(const PrivateLabelReviewRefreshRequested()),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: BlocBuilder<PrivateLabelReviewBloc, PrivateLabelReviewState>(
          builder: (context, state) {
            return RefreshIndicator(
              onRefresh: () async {
                final bloc = context.read<PrivateLabelReviewBloc>()
                  ..add(const PrivateLabelReviewRefreshRequested());
                await bloc.stream
                    .firstWhere((s) => s.status != PrivateLabelReviewStatusView.loading)
                    .timeout(const Duration(seconds: 20), onTimeout: () => bloc.state);
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 768;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: _centered(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Toolbar(state: state, desktop: desktop),
                                const SizedBox(height: 12),
                                _SummaryStrip(state: state),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ..._body(context, state, desktop),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  static Widget _centered(Widget child) => Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: child),
      );

  List<Widget> _body(BuildContext context, PrivateLabelReviewState state, bool desktop) {
    final cs = Theme.of(context).colorScheme;

    if (state.status == PrivateLabelReviewStatusView.loading && state.audits.isEmpty) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
      ];
    }
    if (state.status == PrivateLabelReviewStatusView.failure && state.audits.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Empty(
            icon: Icons.cloud_off_rounded,
            iconColor: cs.error,
            title: state.errorMessage ?? 'حصل خطأ أثناء التحميل',
          ),
        ),
      ];
    }

    final groups = state.groupedByBranch;
    if (groups.isEmpty) {
      final isAll = state.filter == PrivateLabelReviewFilter.all;
      final isPending = state.filter == PrivateLabelReviewFilter.pending;
      final hasDate = state.date != null;

      final String emptyTitle;
      if (isAll) {
        emptyTitle = hasDate ? 'لا توجد توثيقات مرفوعة في هذا اليوم' : 'لا توجد أي توثيقات مرفوعة حالياً';
      } else if (isPending) {
        emptyTitle = 'تمت مراجعة جميع التوثيقات بنجاح';
      } else if (state.filter == PrivateLabelReviewFilter.priceIssues) {
        emptyTitle = 'لا توجد مخالفات أسعار مسجلة';
      } else {
        emptyTitle = 'لا توجد توثيقات مرفوضة';
      }

      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Empty(
            icon: isPending ? Icons.check_circle_outline_rounded : (isAll ? Icons.inbox_rounded : Icons.task_alt_rounded),
            iconColor: isPending ? cs.primary : cs.onSurfaceVariant,
            title: emptyTitle,
          ),
        ),
      ];
    }

    return [
      for (final entry in groups.entries)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          sliver: SliverToBoxAdapter(
            child: _centered(
              _BranchGroup(
                branch: entry.key,
                audits: entry.value,
                desktop: desktop,
                savingAuditId: state.savingAuditId,
                onTap: (a) => _openAudit(context, a, state.products),
                onEdit: (a) => _handleEdit(context, a, state.products),
                onDelete: (a) => _handleDelete(context, a),
              ),
            ),
          ),
        ),
    ];
  }
}

// ─────────────────────────── Toolbar ───────────────────────────

class _Toolbar extends StatelessWidget {
  final PrivateLabelReviewState state;
  final bool desktop;

  const _Toolbar({required this.state, required this.desktop});

  @override
  Widget build(BuildContext context) {
    final statusFilter = _StatusFilterDropdown(state: state);
    final branchFilter = _BranchFilterButton(state: state);
    final productFilter = _ProductFilterButton(state: state);
    final marketerFilter = _MarketerFilterButton(state: state);

    if (desktop) {
      return Row(
        children: [
          SizedBox(width: 220, child: statusFilter),
          const SizedBox(width: 10),
          SizedBox(width: 200, child: branchFilter),
          const SizedBox(width: 10),
          SizedBox(width: 220, child: productFilter),
          const SizedBox(width: 10),
          SizedBox(width: 200, child: marketerFilter),
          const Spacer(),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: statusFilter),
            const SizedBox(width: 8),
            Expanded(child: branchFilter),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: productFilter),
            const SizedBox(width: 8),
            Expanded(child: marketerFilter),
          ],
        ),
      ],
    );
  }
}

class _StatusFilterDropdown extends StatelessWidget {
  final PrivateLabelReviewState state;

  const _StatusFilterDropdown({required this.state});

  static IconData _iconFor(PrivateLabelReviewFilter filter) {
    switch (filter) {
      case PrivateLabelReviewFilter.all:
        return Icons.apps_rounded;
      case PrivateLabelReviewFilter.pending:
        return Icons.hourglass_top_rounded;
      case PrivateLabelReviewFilter.priceIssues:
        return Icons.price_change_rounded;
      case PrivateLabelReviewFilter.rejected:
        return Icons.block_rounded;
    }
  }

  static String _labelFor(PrivateLabelReviewFilter filter) {
    switch (filter) {
      case PrivateLabelReviewFilter.all:
        return 'الكل';
      case PrivateLabelReviewFilter.pending:
        return 'بانتظار المراجعة';
      case PrivateLabelReviewFilter.priceIssues:
        return 'أسعار مختلفة';
      case PrivateLabelReviewFilter.rejected:
        return 'مرفوض';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bloc = context.read<PrivateLabelReviewBloc>();
    final current = state.filter;
    final currentCount = state.countFor(current);

    return Theme(
      data: theme.copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: cs.surfaceContainerHigh,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      child: PopupMenuButton<PrivateLabelReviewFilter>(
        tooltip: 'فلترة بحالة المراجعة',
        offset: const Offset(0, 48),
        onSelected: (f) => bloc.add(PrivateLabelReviewFilterChanged(f)),
        itemBuilder: (context) => [
          for (final f in PrivateLabelReviewFilter.values)
            PopupMenuItem<PrivateLabelReviewFilter>(
              value: f,
              child: Row(
                children: [
                  Icon(
                    _iconFor(f),
                    size: 18,
                    color: current == f ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _labelFor(f),
                      style: TextStyle(
                        fontWeight: current == f ? FontWeight.bold : FontWeight.normal,
                        color: current == f ? cs.primary : cs.onSurface,
                      ),
                    ),
                  ),
                  _CountBadge(count: state.countFor(f), isActive: current == f),
                  if (current == f) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_rounded, size: 18, color: cs.primary),
                  ],
                ],
              ),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: current != PrivateLabelReviewFilter.all
                  ? cs.primary.withValues(alpha: 0.5)
                  : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _iconFor(current),
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _labelFor(current),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _CountBadge(count: currentCount, isActive: true),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final bool isActive;

  const _CountBadge({required this.count, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? cs.primary.withValues(alpha: 0.12)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isActive ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BranchFilterButton extends StatelessWidget {
  final PrivateLabelReviewState state;

  const _BranchFilterButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bloc = context.read<PrivateLabelReviewBloc>();
    final branches = state.allAvailableBranches;
    final selected = state.selectedBranch;

    return Theme(
      data: theme.copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: cs.surfaceContainerHigh,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      child: PopupMenuButton<String?>(
        tooltip: 'فلترة بفروع فتح الله',
        offset: const Offset(0, 48),
        onSelected: (branch) => bloc.add(PrivateLabelReviewBranchSelected(branch)),
        itemBuilder: (context) => [
          PopupMenuItem<String?>(
            value: null,
            child: Row(
              children: [
                Icon(Icons.storefront_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('كل الفروع', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (selected == null) Icon(Icons.check_rounded, size: 18, color: cs.primary),
              ],
            ),
          ),
          if (branches.isNotEmpty) const PopupMenuDivider(),
          for (final b in branches)
            PopupMenuItem<String?>(
              value: b,
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        fontWeight: selected == b ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected == b) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_rounded, size: 18, color: cs.primary),
                  ],
                ],
              ),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected != null ? cs.primary.withValues(alpha: 0.08) : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected != null ? cs.primary.withValues(alpha: 0.6) : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.storefront_rounded,
                size: 18,
                color: selected != null ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected ?? 'كل الفروع',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: selected != null ? cs.primary : cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: selected != null ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductFilterButton extends StatelessWidget {
  final PrivateLabelReviewState state;

  const _ProductFilterButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bloc = context.read<PrivateLabelReviewBloc>();
    final availableProducts = state.allAvailableProducts.isNotEmpty
        ? state.allAvailableProducts
        : PrivateLabelProduct.defaultCatalog('fathalla').map((p) => p.name).toList();
    final selected = state.selectedProduct;
    final selectedCatalogProduct = selected == null
        ? null
        : (state.productForName(selected) ??
            PrivateLabelProduct.defaultCatalog('fathalla')
                .where((p) => p.name == selected)
                .firstOrNull);
    final hasThumb = selectedCatalogProduct?.imageUrl != null &&
        selectedCatalogProduct!.imageUrl!.trim().isNotEmpty;

    return Theme(
      data: theme.copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: cs.surfaceContainerHigh,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      child: PopupMenuButton<String?>(
        tooltip: 'فلترة بمنتجات الكتالوج',
        offset: const Offset(0, 48),
        onSelected: (productName) => bloc.add(PrivateLabelReviewProductSelected(productName)),
        itemBuilder: (context) => [
          PopupMenuItem<String?>(
            value: null,
            child: Row(
              children: [
                Icon(Icons.inventory_2_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('كل المنتجات', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                _CountBadge(count: state.countForProduct(null), isActive: selected == null),
                if (selected == null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_rounded, size: 18, color: cs.primary),
                ],
              ],
            ),
          ),
          if (availableProducts.isNotEmpty) const PopupMenuDivider(),
          for (final pName in availableProducts)
            _buildProductMenuItem(cs, pName, selected == pName),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected != null ? cs.primary.withValues(alpha: 0.08) : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected != null ? cs.primary.withValues(alpha: 0.6) : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              if (hasThumb)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PrivateLabelImage(path: selectedCatalogProduct.imageUrl!),
                )
              else
                Icon(
                  Icons.inventory_2_rounded,
                  size: 18,
                  color: selected != null ? cs.primary : cs.onSurfaceVariant,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected ?? 'كل المنتجات',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: selected != null ? cs.primary : cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: selected != null ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String?> _buildProductMenuItem(
    ColorScheme cs,
    String pName,
    bool isSelected,
  ) {
    final catalogProd = state.productForName(pName) ??
        PrivateLabelProduct.defaultCatalog('fathalla')
            .where((p) => p.name == pName)
            .firstOrNull;
    final itemHasImage =
        catalogProd?.imageUrl != null && catalogProd!.imageUrl!.trim().isNotEmpty;
    return PopupMenuItem<String?>(
      value: pName,
      child: Row(
        children: [
          if (itemHasImage)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              clipBehavior: Clip.antiAlias,
              child: PrivateLabelImage(path: catalogProd.imageUrl!),
            )
          else
            Icon(Icons.inventory_2_outlined, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pName,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _CountBadge(
            count: state.countForProduct(pName),
            isActive: isSelected,
          ),
          if (isSelected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_rounded, size: 18, color: cs.primary),
          ],
        ],
      ),
    );
  }
}

class _MarketerFilterButton extends StatelessWidget {
  final PrivateLabelReviewState state;

  const _MarketerFilterButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bloc = context.read<PrivateLabelReviewBloc>();
    final marketers = state.allAvailableMarketers;
    final selected = state.selectedMarketer;

    return Theme(
      data: theme.copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: cs.surfaceContainerHigh,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      child: PopupMenuButton<String?>(
        tooltip: 'فلترة بالمسوّق',
        offset: const Offset(0, 48),
        onSelected: (marketer) => bloc.add(PrivateLabelReviewMarketerSelected(marketer)),
        itemBuilder: (context) => [
          PopupMenuItem<String?>(
            value: null,
            child: Row(
              children: [
                Icon(Icons.groups_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('كل المسوّقين', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (selected == null) Icon(Icons.check_rounded, size: 18, color: cs.primary),
              ],
            ),
          ),
          if (marketers.isNotEmpty) const PopupMenuDivider(),
          for (final m in marketers)
            PopupMenuItem<String?>(
              value: m,
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      m,
                      style: TextStyle(
                        fontWeight: selected == m ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected == m) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_rounded, size: 18, color: cs.primary),
                  ],
                ],
              ),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected != null ? cs.primary.withValues(alpha: 0.08) : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected != null ? cs.primary.withValues(alpha: 0.6) : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.groups_rounded,
                size: 18,
                color: selected != null ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected ?? 'كل المسوّقين',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: selected != null ? cs.primary : cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: selected != null ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Summary Strip ───────────────────────────

class _SummaryStrip extends StatelessWidget {
  final PrivateLabelReviewState state;

  const _SummaryStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bloc = context.read<PrivateLabelReviewBloc>();
    final branches = state.filteredAudits.map((a) => a.branchName).toSet().length;
    final marketers = state.filteredAudits.map((a) => a.delegateUid).toSet().length;
    final issues = state.countFor(PrivateLabelReviewFilter.priceIssues);

    return AnimatedSwitcher(
      duration: AppMotionDurations.medium1,
      reverseDuration: AppMotionDurations.short3,
      child: state.audits.isEmpty &&
              state.selectedBranch == null &&
              state.selectedProduct == null &&
              state.selectedMarketer == null
          ? const SizedBox.shrink()
          : Wrap(
              key: ValueKey(
                '${state.date}-${state.audits.length}-$issues-${state.selectedBranch}-${state.selectedProduct}-${state.selectedMarketer}',
              ),
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Metric(icon: Icons.storefront_rounded, label: '$branches فرع', color: cs.primary),
                _Metric(icon: Icons.groups_rounded, label: '$marketers مسوّق', color: cs.primary),
                _Metric(
                  icon: Icons.photo_library_rounded,
                  label: '${state.filteredAudits.length} توثيق',
                  color: cs.primary,
                ),
                if (issues > 0)
                  _Metric(icon: Icons.price_change_rounded, label: '$issues مخالفة سعر', color: cs.tertiary),

                // Active date chip
                if (state.date != null)
                  InputChip(
                    avatar: Icon(Icons.calendar_month_rounded, size: 16, color: cs.primary),
                    label: Text(
                      state.date == PrivateLabelDates.dayKey(DateTime.now())
                          ? 'تاريخ: النهارده'
                          : 'تاريخ: ${PrivateLabelLabels.dayTitle(state.date!)}',
                    ),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    tooltip: 'إلغاء فلترة التاريخ وعرض كل التواريخ',
                    onDeleted: () => bloc.add(const PrivateLabelReviewDateChanged(null)),
                  ),

                // Active branch filter chip
                if (state.selectedBranch != null)
                  InputChip(
                    avatar: Icon(Icons.storefront_rounded, size: 16, color: cs.primary),
                    label: Text('فرع: ${state.selectedBranch}'),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    onDeleted: () => bloc.add(const PrivateLabelReviewBranchSelected(null)),
                  ),

                // Active product filter chip
                if (state.selectedProduct != null)
                  InputChip(
                    avatar: Icon(Icons.inventory_2_rounded, size: 16, color: cs.primary),
                    label: Text('منتج: ${state.selectedProduct}'),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    onDeleted: () => bloc.add(const PrivateLabelReviewProductSelected(null)),
                  ),

                // Active marketer filter chip
                if (state.selectedMarketer != null)
                  InputChip(
                    avatar: Icon(Icons.person_rounded, size: 16, color: cs.primary),
                    label: Text('مسوّق: ${state.selectedMarketer}'),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    onDeleted: () => bloc.add(const PrivateLabelReviewMarketerSelected(null)),
                  ),
              ],
            ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Metric({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Branch Group ───────────────────────────

class _BranchGroup extends StatelessWidget {
  final String branch;
  final List<PrivateLabelAudit> audits;
  final bool desktop;
  final String? savingAuditId;
  final ValueChanged<PrivateLabelAudit> onTap;
  final ValueChanged<PrivateLabelAudit>? onEdit;
  final ValueChanged<PrivateLabelAudit>? onDelete;

  const _BranchGroup({
    required this.branch,
    required this.audits,
    required this.desktop,
    required this.savingAuditId,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = audits.where((a) => a.reviewStatus == PrivateLabelReviewStatus.pending).length;

    final tiles = [
      for (final a in audits)
        PrivateLabelAuditTile(
          audit: a,
          showDelegate: true,
          isBusy: savingAuditId == a.id,
          onTap: () => onTap(a),
          onEdit: onEdit != null ? () => onEdit!(a) : null,
          onDelete: onDelete != null ? () => onDelete!(a) : null,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.storefront_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  branch,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${audits.length} توثيق${pending > 0 ? ' • $pending بانتظار المراجعة' : ''}',
                style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (desktop)
          LayoutBuilder(
            builder: (context, c) {
              final itemWidth = (c.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [for (final t in tiles) SizedBox(width: itemWidth, child: t)],
              );
            },
          )
        else
          for (final t in tiles) ...[t, const SizedBox(height: 8)],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;

  const _Empty({required this.icon, required this.iconColor, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: iconColor.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
