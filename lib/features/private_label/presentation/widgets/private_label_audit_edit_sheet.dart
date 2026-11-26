import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_capture_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Shows modal bottom sheet for editing an existing private label audit.
Future<PrivateLabelAudit?> showPrivateLabelAuditEditSheet({
  required BuildContext context,
  required PrivateLabelAudit audit,
  required List<PrivateLabelProduct> products,
}) {
  return showPrivateLabelSheet<PrivateLabelAudit>(
    context: context,
    heightFactor: 0.85,
    builder: (ctx, layout) => _AuditEditSheet(
      layout: layout,
      audit: audit,
      products: products,
    ),
  );
}

class _AuditEditSheet extends StatefulWidget {
  final PrivateLabelSheetLayout layout;
  final PrivateLabelAudit audit;
  final List<PrivateLabelProduct> products;

  const _AuditEditSheet({
    required this.layout,
    required this.audit,
    required this.products,
  });

  @override
  State<_AuditEditSheet> createState() => _AuditEditSheetState();
}

class _AuditEditSheetState extends State<_AuditEditSheet> {
  late String _productName = widget.audit.productName;
  late final TextEditingController _priceCtrl = TextEditingController(
    text: widget.audit.shelfPrice > 0 ? widget.audit.shelfPrice.toStringAsFixed(2) : '',
  );
  late final TextEditingController _barcodeCtrl =
      TextEditingController(text: widget.audit.barcode ?? '');
  late final TextEditingController _notesCtrl =
      TextEditingController(text: widget.audit.notes ?? '');

  late PrivateLabelStockStatus _stock = widget.audit.stockStatus;
  String? _productId;
  double? _referencePrice;

  @override
  void initState() {
    super.initState();
    _productId = widget.audit.productId;
    _referencePrice = widget.audit.referencePrice;
    _priceCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _barcodeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onProductSelected(PrivateLabelProduct p) {
    setState(() {
      _productId = p.id;
      _productName = p.name;
      _referencePrice = p.referencePrice;
      _barcodeCtrl.text = p.barcode ?? '';
    });
  }

  double? get _parsedPrice => parsePrivateLabelPrice(_priceCtrl.text);

  bool get _isValid =>
      _productName.trim().isNotEmpty &&
      _parsedPrice != null &&
      _parsedPrice! > 0;

  void _submit() {
    if (!_isValid) return;
    final updated = widget.audit.copyWith(
      productName: _productName.trim(),
      productId: _productId,
      referencePrice: _referencePrice,
      shelfPrice: _parsedPrice!,
      stockStatus: _stock,
      barcode: _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final parsed = _parsedPrice;
    final baseCatalog = (widget.products.isNotEmpty
            ? widget.products
            : PrivateLabelProduct.defaultCatalog(widget.audit.organizationUID))
        .where((p) => p.isActive || p.id == _productId || p.name.trim() == _productName.trim())
        .toList();
    final hasCurrent = baseCatalog.any(
      (p) => p.id == _productId || p.name.trim() == _productName.trim(),
    );
    final catalogProducts = [
      if (!hasCurrent && _productName.trim().isNotEmpty)
        PrivateLabelProduct(
          id: _productId ?? 'audit_${widget.audit.id}',
          organizationUID: widget.audit.organizationUID,
          name: _productName.trim(),
          barcode: widget.audit.barcode,
          referencePrice: _referencePrice,
        ),
      ...baseCatalog,
    ];
    final selectedProduct = catalogProducts
        .where((p) => p.id == _productId || p.name.trim() == _productName.trim())
        .firstOrNull;

    return PrivateLabelSheetFrame(
      layout: widget.layout,
      icon: Icons.edit_note_rounded,
      title: 'تعديل بيانات التوثيق',
      subtitle: '${widget.audit.branchName} • ${widget.audit.delegateName}',
      actions: PrivateLabelConnectedActions(
        primaryLabel: 'حفظ التعديلات',
        primaryIcon: Icons.check_rounded,
        primaryColor: cs.primary,
        onPrimary: _isValid ? _submit : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),

          // Catalog Product Dropdown Menu (no manual product typing)
          Text(
            'اختيار المنتج من الكتالوج *',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          PrivateLabelProductDropdownMenu(
            products: catalogProducts,
            selectedProduct: selectedProduct,
            onSelected: _onProductSelected,
          ),
          const SizedBox(height: 14),

          // Shelf Price
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'سعر الرف (ج.م) *',
              prefixIcon: const Icon(Icons.payments_rounded),
              suffixText: 'ج.م',
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),

          if (_referencePrice != null && parsed != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (parsed - _referencePrice!).abs() > PrivateLabelAudit.priceTolerance
                    ? cs.tertiaryContainer.withValues(alpha: 0.4)
                    : const Color(0xFF2E7D32).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    (parsed - _referencePrice!).abs() > PrivateLabelAudit.priceTolerance
                        ? Icons.price_change_rounded
                        : Icons.check_circle_rounded,
                    size: 16,
                    color: (parsed - _referencePrice!).abs() > PrivateLabelAudit.priceTolerance
                        ? cs.onTertiaryContainer
                        : const Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'السعر المعتمد بالكتالوج: ${PrivateLabelLabels.price(_referencePrice!)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: (parsed - _referencePrice!).abs() > PrivateLabelAudit.priceTolerance
                            ? cs.onTertiaryContainer
                            : const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Stock Status
          Text(
            'حالة التواجد على الرف',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TashilConnectedButtonGroup<PrivateLabelStockStatus>(
            width: double.infinity,
            height: 48,
            itemPadding: const EdgeInsets.symmetric(horizontal: 6),
            selectedValue: _stock,
            onSelected: (s) => setState(() => _stock = s),
            items: PrivateLabelStockStatus.values
                .map((s) => TashilConnectedButtonItem<PrivateLabelStockStatus>(
                      value: s,
                      label: PrivateLabelLabels.stock(s),
                      icon: PrivateLabelLabels.stockIcon(s),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),

          // Barcode (Optional)
          TextField(
            controller: _barcodeCtrl,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'الباركود (اختياري)',
              prefixIcon: const Icon(Icons.qr_code_rounded),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Notes (Optional)
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'ملاحظات المسوّق / الفرع (اختياري)',
              prefixIcon: const Icon(Icons.notes_rounded),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
