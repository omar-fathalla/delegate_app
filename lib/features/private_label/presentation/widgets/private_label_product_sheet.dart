import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_review_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_capture_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens the product catalog manager (Marketing Promotion only).
Future<void> showPrivateLabelCatalogSheet({
  required BuildContext context,
  required String organizationUID,
}) {
  final bloc = context.read<PrivateLabelReviewBloc>();
  return showPrivateLabelSheet<void>(
    context: context,
    builder: (ctx, layout) => BlocProvider.value(
      value: bloc,
      child: _CatalogSheet(layout: layout, organizationUID: organizationUID),
    ),
  );
}

/// Add / edit a single catalog product. Returns the product to save.
Future<PrivateLabelProduct?> showPrivateLabelProductSheet({
  required BuildContext context,
  required String organizationUID,
  PrivateLabelProduct? product,
}) {
  return showPrivateLabelSheet<PrivateLabelProduct>(
    context: context,
    heightFactor: 0.7,
    builder: (ctx, layout) => _ProductSheet(
      layout: layout,
      organizationUID: organizationUID,
      product: product,
    ),
  );
}

class _CatalogSheet extends StatefulWidget {
  final PrivateLabelSheetLayout layout;
  final String organizationUID;

  const _CatalogSheet({required this.layout, required this.organizationUID});

  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _edit([PrivateLabelProduct? product]) async {
    final bloc = context.read<PrivateLabelReviewBloc>();
    final saved = await showPrivateLabelProductSheet(
      context: context,
      organizationUID: widget.organizationUID,
      product: product,
    );
    if (saved != null) bloc.add(PrivateLabelReviewProductSaved(saved));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BlocBuilder<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      buildWhen: (p, c) => p.products != c.products || p.isSavingProduct != c.isSavingProduct,
      builder: (context, state) {
        final q = _searchCtrl.text.trim().toLowerCase();
        final products = q.isEmpty
            ? state.products
            : state.products
                .where((p) =>
                    p.name.toLowerCase().contains(q) ||
                    (p.barcode ?? '').contains(q) ||
                    (p.category ?? '').toLowerCase().contains(q))
                .toList();

        return PrivateLabelSheetFrame(
          layout: widget.layout,
          icon: Icons.inventory_2_rounded,
          title: 'كتالوج منتجات البرايفت ليبل',
          subtitle: '${state.products.length} منتج • السعر المعتمد بيستخدم لاكتشاف مخالفات الأسعار',
          headerTrailing: state.isSavingProduct
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
          actions: PrivateLabelConnectedActions(
            secondaryLabel: 'إغلاق',
            primaryLabel: 'إضافة منتج',
            primaryIcon: Icons.add_rounded,
            onPrimary: () => _edit(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              SearchBar(
                controller: _searchCtrl,
                hintText: 'ابحث بالاسم أو الباركود أو القسم',
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerLow),
                side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant)),
                constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
              ),
              const SizedBox(height: 12),
              if (products.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 44, color: cs.outline),
                      const SizedBox(height: 8),
                      Text(
                        state.products.isEmpty ? 'لسه مفيش منتجات في الكتالوج' : 'مفيش نتائج',
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                for (final p in products) ...[
                  _ProductRow(product: p, onTap: () => _edit(p)),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _ProductRow extends StatelessWidget {
  final PrivateLabelProduct product;
  final VoidCallback onTap;

  const _ProductRow({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final details = [
      if (product.category != null && product.category!.isNotEmpty) product.category!,
      if (product.barcode != null && product.barcode!.isNotEmpty) product.barcode!,
    ].join(' • ');

    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: cs.primary.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: product.isActive ? 1 : 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.sell_rounded, size: 18, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: product.isActive ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!product.isActive)
                PrivateLabelStatusPill(icon: Icons.pause_circle_rounded, label: 'موقوف', color: cs.outline)
              else
                Text(
                  product.referencePrice == null ? '—' : PrivateLabelLabels.price(product.referencePrice!),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
                ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductSheet extends StatefulWidget {
  final PrivateLabelSheetLayout layout;
  final String organizationUID;
  final PrivateLabelProduct? product;

  const _ProductSheet({required this.layout, required this.organizationUID, this.product});

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late final _nameCtrl = TextEditingController(text: widget.product?.name ?? '');
  late final _barcodeCtrl = TextEditingController(text: widget.product?.barcode ?? '');
  late final _categoryCtrl = TextEditingController(text: widget.product?.category ?? '');
  late final _priceCtrl = TextEditingController(
    text: widget.product?.referencePrice == null ? '' : _formatPrice(widget.product!.referencePrice!),
  );
  late bool _isActive = widget.product?.isActive ?? true;

  static String _formatPrice(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _priceCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _categoryCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  double? get _price => _priceCtrl.text.trim().isEmpty ? null : parsePrivateLabelPrice(_priceCtrl.text);

  bool get _isValid =>
      _nameCtrl.text.trim().isNotEmpty && (_priceCtrl.text.trim().isEmpty || (_price ?? 0) > 0);

  void _save() {
    if (!_isValid) return;
    String? clean(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.of(context).pop(PrivateLabelProduct(
      id: widget.product?.id ?? '',
      organizationUID: widget.organizationUID,
      name: _nameCtrl.text.trim(),
      barcode: clean(_barcodeCtrl),
      category: clean(_categoryCtrl),
      referencePrice: _price,
      isActive: _isActive,
    ));
  }

  InputDecoration _decoration(ColorScheme cs, String label, IconData icon, {String? suffixText}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixText: suffixText,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEdit = widget.product != null;

    return PrivateLabelSheetFrame(
      layout: widget.layout,
      icon: isEdit ? Icons.edit_rounded : Icons.add_box_rounded,
      title: isEdit ? 'تعديل منتج' : 'منتج جديد',
      subtitle: 'منتجات فتح الله - البرايفت ليبل',
      actions: PrivateLabelConnectedActions(
        primaryLabel: 'حفظ',
        primaryIcon: Icons.save_rounded,
        onPrimary: _isValid ? _save : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: _decoration(cs, 'اسم المنتج *', Icons.label_rounded),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: _decoration(cs, 'السعر المعتمد', Icons.payments_rounded, suffixText: 'ج.م'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _barcodeCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: _decoration(cs, 'الباركود', Icons.qr_code_rounded),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            textInputAction: TextInputAction.done,
            decoration: _decoration(cs, 'القسم (مثلاً: أرز، زيوت، مكرونة)', Icons.category_rounded),
          ),
          if (isEdit) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              secondary: Icon(_isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded),
              title: const Text('المنتج نشط'),
              subtitle: const Text('المنتج الموقوف مش بيظهر في اقتراحات المسوّقين'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
