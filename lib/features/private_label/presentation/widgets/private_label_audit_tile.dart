import 'package:delegate_app/features/private_label/presentation/widgets/private_label_photo_pair.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// List tile for a synced audit (marketer history + auditor triage).
class PrivateLabelAuditTile extends StatelessWidget {
  final PrivateLabelAudit audit;
  final VoidCallback? onTap;
  final bool showDelegate;
  final bool isBusy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const PrivateLabelAuditTile({
    super.key,
    required this.audit,
    this.onTap,
    this.showDelegate = false,
    this.isBusy = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = PrivateLabelLabels.reviewColor(audit.reviewStatus, cs);
    final accent = audit.hasPriceMismatch && audit.reviewStatus == PrivateLabelReviewStatus.pending
        ? cs.tertiary
        : statusColor;

    final photos = [
      if (audit.productPhotoUrl.isNotEmpty) audit.productPhotoUrl,
      if (audit.pricePhotoUrl.isNotEmpty) audit.pricePhotoUrl,
    ];
    final coverPhoto = photos.isNotEmpty ? photos.first : '';
    final count = photos.length;

    return _TileShell(
      accent: accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Top row: Single Thumbnail + Product Name + Price Chip + Menu ───
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SingleThumb(
                path: coverPhoto,
                count: count,
                onTap: onTap,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audit.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        PrivateLabelStatusPill(
                          icon: Icons.payments_rounded,
                          label: PrivateLabelLabels.price(audit.shelfPrice),
                          color: cs.onSurfaceVariant,
                        ),
                        if (audit.hasPriceMismatch)
                          PrivateLabelStatusPill(
                            icon: Icons.price_change_rounded,
                            label: 'الرسمي ${PrivateLabelLabels.price(audit.referencePrice!)}',
                            color: cs.tertiary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isBusy)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 8),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 20, color: cs.onSurfaceVariant),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                  tooltip: 'خيارات',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (val) {
                    if (val == 'edit') onEdit?.call();
                    if (val == 'delete') onDelete?.call();
                  },
                  itemBuilder: (ctx) => [
                    if (onEdit != null)
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_note_rounded, size: 20, color: cs.primary),
                            const SizedBox(width: 10),
                            const Text('تعديل التوثيق'),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
                            const SizedBox(width: 10),
                            Text('حذف التوثيق', style: TextStyle(color: cs.error)),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 10),

          // ─── Bottom row: Marketer/Branch Name + Time (Right) | Status Chip (Left) ───
          Row(
            children: [
              Icon(
                showDelegate ? Icons.person_outline_rounded : Icons.storefront_rounded,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  showDelegate
                      ? '${audit.delegateName} · ${PrivateLabelLabels.time(audit.capturedAt)}'
                      : '${audit.branchName} · ${PrivateLabelLabels.time(audit.capturedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PrivateLabelStatusPill(
                icon: PrivateLabelLabels.reviewIcon(audit.reviewStatus),
                label: PrivateLabelLabels.review(audit.reviewStatus),
                color: statusColor,
              ),
              if (audit.hasClockSkewWarning) ...[
                const SizedBox(width: 4),
                PrivateLabelStatusPill(
                  icon: Icons.schedule_rounded,
                  label: 'متأخر',
                  color: cs.error,
                ),
              ],
            ],
          ),

          if (audit.reviewStatus == PrivateLabelReviewStatus.rejected &&
              (audit.reviewNotes ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'سبب الرفض: ${audit.reviewNotes}',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
        ],
      ),
    );
  }
}

/// List tile for an audit still waiting on the device.
class PrivateLabelDraftTile extends StatelessWidget {
  final PrivateLabelAuditDraft draft;
  final VoidCallback? onTap;

  const PrivateLabelDraftTile({super.key, required this.draft, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final photos = [
      if (draft.productImagePath.isNotEmpty) draft.productImagePath,
      if (draft.priceImagePath.isNotEmpty) draft.priceImagePath,
    ];
    final coverPhoto = photos.isNotEmpty ? photos.first : '';
    final count = photos.length;

    return _TileShell(
      accent: cs.secondary,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SingleThumb(path: coverPhoto, count: count, onTap: onTap),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    PrivateLabelStatusPill(
                      icon: Icons.payments_rounded,
                      label: PrivateLabelLabels.price(draft.shelfPrice),
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.storefront_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${draft.branchName} · ${PrivateLabelLabels.time(draft.capturedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PrivateLabelStatusPill(
                icon: Icons.save_rounded,
                label: 'متوثق محلياً',
                color: cs.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TileShell extends StatelessWidget {
  final Color accent;
  final Widget child;
  final VoidCallback? onTap;

  const _TileShell({required this.accent, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: cs.primary.withValues(alpha: 0.05),
        child: PrivateLabelAccentContainer(
          accent: accent,
          background: cs.surfaceContainerLow,
          radius: 16,
          outlined: true,
          child: child,
        ),
      ),
    );
  }
}

class _SingleThumb extends StatelessWidget {
  final String path;
  final int count;
  final VoidCallback? onTap;

  const _SingleThumb({
    required this.path,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 58,
          height: 58,
          color: cs.surfaceContainerHigh,
          child: Stack(
            fit: StackFit.expand,
            children: [
              path.isEmpty
                  ? Icon(Icons.image_rounded, color: cs.outline)
                  : PrivateLabelImage(path: path, isThumbnail: true),
              if (count > 1)
                PositionedDirectional(
                  bottom: 3,
                  end: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.collections_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2.5),
                        Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
