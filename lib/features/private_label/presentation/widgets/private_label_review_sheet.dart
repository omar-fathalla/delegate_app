import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_audit_edit_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_photo_pair.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Decision returned by [showPrivateLabelReviewSheet].
class PrivateLabelReviewDecision {
  final PrivateLabelReviewStatus status;
  final String? notes;

  const PrivateLabelReviewDecision(this.status, this.notes);
}

/// Responsive M3 confirmation bottom sheet / dialog for deleting an audit.
Future<bool> confirmPrivateLabelAuditDeletion({
  required BuildContext context,
  required PrivateLabelAudit audit,
}) async {
  final confirmed = await showPrivateLabelSheet<bool>(
    context: context,
    heightFactor: null,
    builder: (ctx, layout) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      return PrivateLabelSheetFrame(
        layout: layout,
        icon: Icons.delete_forever_rounded,
        title: 'حذف التوثيق',
        subtitle: '${audit.branchName} • ${audit.delegateName}',
        actions: PrivateLabelConnectedActions(
          primaryLabel: 'حذف نهائي',
          primaryIcon: Icons.delete_forever_rounded,
          primaryColor: cs.error,
          onPrimaryColor: cs.onError,
          secondaryLabel: 'إلغاء',
          onSecondary: () => Navigator.of(ctx).pop(false),
          onPrimary: () => Navigator.of(ctx).pop(true),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            PrivateLabelAccentContainer(
              accent: cs.error,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 22, color: cs.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'هل أنت متأكد من حذف هذا التوثيق نهائياً؟\nسيتم مسح بيانات التوثيق وصور الرف وتحديث ملخص اليوم.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          audit.productName,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'سعر الرف: ${PrivateLabelLabels.price(audit.shelfPrice)} · ${PrivateLabelLabels.time(audit.capturedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}

Future<PrivateLabelReviewDecision?> showPrivateLabelReviewSheet({
  required BuildContext context,
  required PrivateLabelAudit audit,
  List<PrivateLabelProduct> products = const [],
  ValueChanged<PrivateLabelAudit>? onEdit,
  VoidCallback? onDelete,
}) {
  return showPrivateLabelSheet<PrivateLabelReviewDecision>(
    context: context,
    builder: (ctx, layout) => _ReviewSheet(
      layout: layout,
      audit: audit,
      products: products,
      onEdit: onEdit,
      onDelete: onDelete,
    ),
  );
}

class _ReviewSheet extends StatefulWidget {
  final PrivateLabelSheetLayout layout;
  final PrivateLabelAudit audit;
  final List<PrivateLabelProduct> products;
  final ValueChanged<PrivateLabelAudit>? onEdit;
  final VoidCallback? onDelete;

  const _ReviewSheet({
    required this.layout,
    required this.audit,
    this.products = const [],
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  static const _decisions = [
    PrivateLabelReviewStatus.approved,
    PrivateLabelReviewStatus.priceIssue,
    PrivateLabelReviewStatus.rejected,
  ];

  late PrivateLabelAudit _audit = widget.audit;
  late PrivateLabelReviewStatus _status = _initialStatus();
  late final TextEditingController _notesCtrl =
      TextEditingController(text: widget.audit.reviewNotes ?? '');

  PrivateLabelReviewStatus _initialStatus() {
    final a = _audit;
    if (a.reviewStatus != PrivateLabelReviewStatus.pending) return a.reviewStatus;
    return a.hasPriceMismatch ? PrivateLabelReviewStatus.priceIssue : PrivateLabelReviewStatus.approved;
  }

  @override
  void initState() {
    super.initState();
    _notesCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleEdit() async {
    final updated = await showPrivateLabelAuditEditSheet(
      context: context,
      audit: _audit,
      products: widget.products,
    );
    if (updated != null && mounted) {
      setState(() {
        _audit = updated;
      });
      widget.onEdit?.call(updated);
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await confirmPrivateLabelAuditDeletion(
      context: context,
      audit: _audit,
    );
    if (confirmed && mounted) {
      Navigator.of(context).pop();
      widget.onDelete?.call();
    }
  }

  bool get _notesRequired => _status == PrivateLabelReviewStatus.rejected;

  bool get _isValid => !_notesRequired || _notesCtrl.text.trim().isNotEmpty;

  void _submit() {
    if (!_isValid) return;
    final notes = _notesCtrl.text.trim();
    Navigator.of(context).pop(PrivateLabelReviewDecision(_status, notes.isEmpty ? null : notes));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = _audit;
    final primaryColor = PrivateLabelLabels.reviewColor(_status, cs);

    return PrivateLabelSheetFrame(
      layout: widget.layout,
      icon: Icons.fact_check_rounded,
      title: a.productName,
      subtitle: '${a.branchName} • ${a.delegateName}',
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrivateLabelStatusPill(
            icon: PrivateLabelLabels.reviewIcon(a.reviewStatus),
            label: PrivateLabelLabels.review(a.reviewStatus),
            color: PrivateLabelLabels.reviewColor(a.reviewStatus, cs),
          ),
          if (widget.onEdit != null || widget.onDelete != null) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 20, color: cs.onSurfaceVariant),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 20,
              tooltip: 'خيارات التوثيق',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (val) {
                if (val == 'edit') _handleEdit();
                if (val == 'delete') _handleDelete();
              },
              itemBuilder: (ctx) => [
                if (widget.onEdit != null)
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
                if (widget.onDelete != null)
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
        ],
      ),
      actions: PrivateLabelConnectedActions(
        primaryLabel: _primaryLabel,
        primaryIcon: PrivateLabelLabels.reviewIcon(_status),
        primaryColor: primaryColor,
        onPrimaryColor: _onColor(cs),
        onPrimary: _isValid ? _submit : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          PrivateLabelPhotoPair(
            productPhoto: a.productPhotoUrl,
            pricePhoto: a.pricePhotoUrl,
            height: 200,
          ),
          const SizedBox(height: 6),
          Text(
            'اضغط على الصورة للتكبير وقراءة بطاقة السعر',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'مقارنة الأسعار',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
              if (widget.onEdit != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: _handleEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('تعديل البيانات'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _PriceComparison(audit: a),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(icon: PrivateLabelLabels.stockIcon(a.stockStatus), label: PrivateLabelLabels.stock(a.stockStatus)),
              _InfoChip(icon: Icons.schedule_rounded, label: PrivateLabelLabels.time(a.capturedAt)),
              if (a.barcode != null && a.barcode!.isNotEmpty)
                _InfoChip(icon: Icons.qr_code_rounded, label: a.barcode!),
            ],
          ),
          if (a.notes != null && a.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            PrivateLabelAccentContainer(
              accent: cs.outline,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_rounded, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ملاحظة المسوّق: ${a.notes}',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (a.hasClockSkewWarning) ...[
            const SizedBox(height: 12),
            PrivateLabelAccentContainer(
              accent: cs.error,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تنبيه: التوثيق اتصور أوفلاين واترفع بعد أكتر من 24 ساعة (أو ساعة الجهاز مختلفة). راجع التاريخ في الصورة.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'القرار',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          TashilConnectedButtonGroup<PrivateLabelReviewStatus>(
            width: double.infinity,
            height: 48.0,
            itemPadding: const EdgeInsets.symmetric(horizontal: 8.0),
            selectedValue: _status,
            onSelected: (s) => setState(() => _status = s),
            items: [
              for (final s in _decisions)
                TashilConnectedButtonItem<PrivateLabelReviewStatus>(
                  value: s,
                  label: PrivateLabelLabels.review(s),
                  icon: PrivateLabelLabels.reviewIcon(s),
                  activeColor: PrivateLabelLabels.reviewColor(s, cs),
                  activeForegroundColor: _onColorFor(s, cs),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _decisionHint,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: _notesRequired ? 'سبب الرفض (إجباري)' : 'ملاحظات للفرع / المسوّق (اختياري)',
              prefixIcon: const Icon(Icons.edit_note_rounded),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          if (a.reviewedByName != null && a.reviewStatus != PrivateLabelReviewStatus.pending) ...[
            const SizedBox(height: 10),
            Text(
              'آخر مراجعة بواسطة ${a.reviewedByName}${a.reviewedAt != null ? ' • ${PrivateLabelLabels.time(a.reviewedAt!)}' : ''}',
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String get _primaryLabel {
    switch (_status) {
      case PrivateLabelReviewStatus.approved:
        return 'اعتماد';
      case PrivateLabelReviewStatus.priceIssue:
        return 'تسجيل مخالفة سعر';
      case PrivateLabelReviewStatus.rejected:
        return 'رفض التوثيق';
      case PrivateLabelReviewStatus.pending:
        return 'حفظ';
    }
  }

  String get _decisionHint {
    switch (_status) {
      case PrivateLabelReviewStatus.approved:
        return 'الصور واضحة والسعر مطابق.';
      case PrivateLabelReviewStatus.priceIssue:
        return 'التوثيق سليم لكن السعر على الرف غلط — الفرع لازم يعدّله. مش بيأثر على نسبة المسوّق.';
      case PrivateLabelReviewStatus.rejected:
        return 'الصور مش واضحة أو مش للمنتج الصح — التوثيق مش هيتحسب للمسوّق.';
      case PrivateLabelReviewStatus.pending:
        return '';
    }
  }

  Color _onColor(ColorScheme cs) => _onColorFor(_status, cs);

  Color _onColorFor(PrivateLabelReviewStatus s, ColorScheme cs) {
    switch (s) {
      case PrivateLabelReviewStatus.approved:
        return cs.onPrimary;
      case PrivateLabelReviewStatus.priceIssue:
        return cs.onTertiary;
      case PrivateLabelReviewStatus.rejected:
        return cs.onError;
      case PrivateLabelReviewStatus.pending:
        return cs.surface;
    }
  }
}

class _PriceComparison extends StatelessWidget {
  final PrivateLabelAudit audit;

  const _PriceComparison({required this.audit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mismatch = audit.hasPriceMismatch;
    final accent = audit.referencePrice == null ? cs.outline : (mismatch ? cs.tertiary : cs.primary);

    Widget cell(String label, String value, {bool strong = false}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        );

    return PrivateLabelAccentContainer(
      accent: accent,
      outlined: true,
      background: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              cell('سعر الرف', PrivateLabelLabels.price(audit.shelfPrice), strong: true),
              cell(
                'السعر المعتمد',
                audit.referencePrice == null ? 'غير محدد' : PrivateLabelLabels.price(audit.referencePrice!),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PrivateLabelStatusPill(
            icon: audit.referencePrice == null
                ? Icons.help_outline_rounded
                : (mismatch ? Icons.price_change_rounded : Icons.check_circle_rounded),
            label: audit.referencePrice == null
                ? 'المنتج مالوش سعر معتمد في الكتالوج'
                : (mismatch
                    ? 'فرق ${PrivateLabelLabels.price((audit.shelfPrice - audit.referencePrice!).abs())}'
                    : 'السعر مطابق'),
            color: accent,
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}
