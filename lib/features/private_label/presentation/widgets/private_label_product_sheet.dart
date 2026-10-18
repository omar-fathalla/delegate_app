import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_review_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_capture_sheet.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_photo_pair.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens the product catalog manager bottom sheet / dialog.
Future<void> showPrivateLabelCatalogSheet({
  required BuildContext context,
  required String organizationUID,
  PrivateLabelReviewBloc? bloc,
  bool readOnly = false,
}) {
  final effectiveBloc = bloc ?? context.read<PrivateLabelReviewBloc>();
  return showPrivateLabelSheet<void>(
    context: context,
    heightFactor: 0.88,
    builder: (ctx, layout) => BlocProvider.value(
      value: effectiveBloc,
      child: _CatalogSheet(
        layout: layout,
        organizationUID: organizationUID,
        readOnly: readOnly,
      ),
    ),
  );
}

/// Opens a read-only product details sheet (للنظر فقط) without edit controls.
Future<void> showPrivateLabelProductDetailsSheet({
  required BuildContext context,
  required PrivateLabelProduct product,
}) {
  return showPrivateLabelSheet<void>(
    context: context,
    heightFactor: 0.72,
    builder: (ctx, layout) => _ProductDetailsSheet(
      layout: layout,
      product: product,
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
    heightFactor: 0.88,
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
  final bool readOnly;

  const _CatalogSheet({
    required this.layout,
    required this.organizationUID,
    this.readOnly = false,
  });

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
    if (widget.readOnly) {
      if (product != null) {
        await showPrivateLabelProductDetailsSheet(
          context: context,
          product: product,
        );
      }
      return;
    }
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
                    (p.barcode ?? '').toLowerCase().contains(q) ||
                    (p.category ?? '').toLowerCase().contains(q))
                .toList();

        return PrivateLabelSheetFrame(
          layout: widget.layout,
          icon: Icons.inventory_2_rounded,
          title: 'كتالوج منتجات البرايفت ليبل',
          subtitle: widget.readOnly
              ? '${state.products.length} منتج • عرض المنتجات والأسعار المعتمدة'
              : '${state.products.length} منتج • السعر المعتمد بيستخدم لاكتشاف مخالفات الأسعار',
          headerTrailing: state.isSavingProduct
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
          actions: widget.readOnly
              ? PrivateLabelConnectedActions(
                  secondaryLabel: 'رجوع',
                  secondaryIcon: Icons.arrow_forward_rounded,
                  primaryLabel: 'إغلاق',
                  primaryIcon: Icons.check_rounded,
                  onPrimary: () => Navigator.of(context).pop(),
                )
              : PrivateLabelConnectedActions(
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
                  PrivateLabelCatalogProductTile(
                    product: p,
                    readOnly: widget.readOnly,
                    onTap: () => _edit(p),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        );
      },
    );
  }
}

/// Reusable catalog product card with thumbnail, price badge, barcode, and edit/view button.
class PrivateLabelCatalogProductTile extends StatelessWidget {
  final PrivateLabelProduct product;
  final VoidCallback onTap;
  final bool readOnly;

  const PrivateLabelCatalogProductTile({
    super.key,
    required this.product,
    required this.onTap,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasImage = product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
              // Product Image Thumbnail
              GestureDetector(
                onTap: hasImage
                    ? () => PrivateLabelZoomViewer.open(
                          context,
                          product.imageUrl!,
                          'catalog_img_${product.id}_${product.name}',
                          product.name,
                        )
                    : onTap,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? Hero(
                          tag: 'catalog_img_${product.id}_${product.name}',
                          child: PrivateLabelImage(
                            path: product.imageUrl!,
                            isThumbnail: true,
                          ),
                        )
                      : Icon(
                          Icons.sell_rounded,
                          size: 24,
                          color: cs.primary,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: product.isActive ? cs.onSurface : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (product.barcode != null && product.barcode!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.qr_code_rounded, size: 13, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    product.barcode!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (product.category != null && product.category!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              product.category!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!product.isActive)
                    PrivateLabelStatusPill(
                      icon: Icons.pause_circle_rounded,
                      label: 'موقوف',
                      color: cs.outline,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        product.referencePrice == null
                            ? '—'
                            : PrivateLabelLabels.price(product.referencePrice!),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        readOnly ? Icons.visibility_rounded : Icons.edit_rounded,
                        size: 13,
                        color: readOnly ? cs.onSurfaceVariant : cs.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        readOnly ? 'عرض' : 'تعديل',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: readOnly ? cs.onSurfaceVariant : cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductDetailsSheet extends StatelessWidget {
  final PrivateLabelSheetLayout layout;
  final PrivateLabelProduct product;

  const _ProductDetailsSheet({
    required this.layout,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasImage = product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

    Widget infoRow(IconData icon, String label, String value, {Color? valueColor}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: cs.primary),
            const SizedBox(width: 10),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PrivateLabelSheetFrame(
      layout: layout,
      icon: Icons.inventory_2_rounded,
      title: product.name,
      subtitle: 'بيانات المنتج في الكتالوج (وضع العرض فقط)',
      headerTrailing: PrivateLabelStatusPill(
        icon: Icons.visibility_rounded,
        label: 'عرض فقط',
        color: cs.primary,
      ),
      actions: PrivateLabelConnectedActions(
        secondaryLabel: 'رجوع',
        secondaryIcon: Icons.arrow_forward_rounded,
        primaryLabel: 'إغلاق',
        primaryIcon: Icons.check_rounded,
        onPrimary: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          if (hasImage) ...[
            GestureDetector(
              onTap: () => PrivateLabelZoomViewer.open(
                context,
                product.imageUrl!,
                'catalog_detail_img_${product.id}_${product.name}',
                product.name,
              ),
              child: Container(
                height: 190,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'catalog_detail_img_${product.id}_${product.name}',
                      child: PrivateLabelImage(path: product.imageUrl!),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'تكبير الصورة',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
            const SizedBox(height: 14),
          ],
          infoRow(
            Icons.label_rounded,
            'اسم المنتج',
            product.name,
          ),
          const SizedBox(height: 8),
          infoRow(
            Icons.payments_rounded,
            'السعر المعتمد',
            product.referencePrice == null
                ? 'غير محدد'
                : PrivateLabelLabels.price(product.referencePrice!),
            valueColor: cs.primary,
          ),
          const SizedBox(height: 8),
          infoRow(
            Icons.qr_code_rounded,
            'الباركود',
            (product.barcode != null && product.barcode!.trim().isNotEmpty)
                ? product.barcode!
                : 'غير مسجل',
          ),
          const SizedBox(height: 8),
          infoRow(
            Icons.category_rounded,
            'القسم / التصنيف',
            (product.category != null && product.category!.trim().isNotEmpty)
                ? product.category!
                : 'غير مصنف',
          ),
          const SizedBox(height: 8),
          infoRow(
            product.isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
            'الحالة في القائمة المنسدلة',
            product.isActive ? 'نشط ومتاح للتصوير' : 'موقوف حالياً',
            valueColor: product.isActive ? cs.primary : cs.outline,
          ),
          const SizedBox(height: 8),
        ],
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
  static final ImagePicker _picker = ImagePicker();

  late final _nameCtrl = TextEditingController(text: widget.product?.name ?? '');
  late final _barcodeCtrl = TextEditingController(text: widget.product?.barcode ?? '');
  late final _categoryCtrl = TextEditingController(text: widget.product?.category ?? '');
  late final _priceCtrl = TextEditingController(
    text: widget.product?.referencePrice == null ? '' : _formatPrice(widget.product!.referencePrice!),
  );
  late String? _imageUrl = widget.product?.imageUrl;
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
    _barcodeCtrl.addListener(() => setState(() {}));
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
      _nameCtrl.text.trim().isNotEmpty &&
      _price != null &&
      _price! > 0;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1400,
        maxHeight: 1400,
        imageQuality: 78,
      );
      if (file == null || !mounted) return;
      setState(() => _imageUrl = file.path);
    } catch (_) {}
  }

  Future<void> _scanBarcode() async {
    final code = await showPrivateLabelSheet<String>(
      context: context,
      heightFactor: 0.75,
      builder: (ctx, layout) => _CatalogBarcodeScannerSheet(layout: layout),
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() {
      _barcodeCtrl.text = code;
    });
  }

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
      imageUrl: (_imageUrl == null || _imageUrl!.trim().isEmpty) ? null : _imageUrl!.trim(),
      isActive: _isActive,
    ));
  }

  InputDecoration _decoration(
    ColorScheme cs,
    String label,
    IconData icon, {
    String? suffixText,
    Widget? suffixIcon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon),
      suffixText: suffixText,
      suffixIcon: suffixIcon,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEdit = widget.product != null;
    final hasImage = _imageUrl != null && _imageUrl!.trim().isNotEmpty;

    return PrivateLabelSheetFrame(
      layout: widget.layout,
      icon: isEdit ? Icons.edit_rounded : Icons.add_box_rounded,
      title: isEdit ? 'تعديل بيانات المنتج' : 'إضافة منتج جديد للكتالوج',
      subtitle: 'يظهر تلقائياً في القائمة المنسدلة (Dropdown Menu) عند التصوير',
      actions: PrivateLabelConnectedActions(
        primaryLabel: isEdit ? 'حفظ التعديلات' : 'إضافة للكتالوج',
        primaryIcon: Icons.save_rounded,
        onPrimary: _isValid ? _save : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),

          // 1. Product Image Section
          Text(
            'صورة المنتج',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? PrivateLabelImage(path: _imageUrl!)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded, size: 28, color: cs.primary),
                            const SizedBox(height: 4),
                            Text(
                              'صورة المنتج',
                              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_rounded, size: 18),
                        label: const Text('تصوير المنتج بالكاميرا'),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded, size: 18),
                        label: const Text('اختيار صورة من المعرض'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. Product Name
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              cs,
              'اسم المنتج *',
              Icons.label_rounded,
              hintText: 'مثال: أرز فتح الله 1 كيلو',
            ),
          ),
          const SizedBox(height: 12),

          // 3. Official Reference Price
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              cs,
              'سعر المنتج المعتمد *',
              Icons.payments_rounded,
              suffixText: 'ج.م',
              hintText: 'مثال: 35',
            ),
          ),
          const SizedBox(height: 12),

          // 4. Barcode + Camera Scanner
          TextField(
            controller: _barcodeCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              cs,
              'باركود المنتج',
              Icons.qr_code_rounded,
              hintText: 'اكتب الباركود أو امسحه بالكاميرا',
              suffixIcon: IconButton(
                tooltip: 'مسح الباركود بالكاميرا',
                icon: Icon(Icons.qr_code_scanner_rounded, color: cs.primary),
                onPressed: _scanBarcode,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 5. Category
          TextField(
            controller: _categoryCtrl,
            textInputAction: TextInputAction.done,
            decoration: _decoration(
              cs,
              'القسم / التصنيف (بقالة جافة، زيوت، منظفات...)',
              Icons.category_rounded,
            ),
          ),

          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            secondary: Icon(
              _isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
              color: _isActive ? cs.primary : cs.outline,
            ),
            title: const Text('إظهار المنتج في القائمة المنسدلة (نشط)'),
            subtitle: const Text('المنتج النشط يظهر للمسوقين عند تصوير وتوثيق الفروع'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CatalogBarcodeScannerSheet extends StatefulWidget {
  final PrivateLabelSheetLayout layout;

  const _CatalogBarcodeScannerSheet({required this.layout});

  @override
  State<_CatalogBarcodeScannerSheet> createState() => _CatalogBarcodeScannerSheetState();
}

class _CatalogBarcodeScannerSheetState extends State<_CatalogBarcodeScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
    facing: CameraFacing.back,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrivateLabelSheetFrame(
      layout: widget.layout,
      icon: Icons.qr_code_scanner_rounded,
      title: 'مسح باركود المنتج',
      subtitle: 'وجّه الكاميرا على باركود العبوة',
      actions: PrivateLabelConnectedActions(
        primaryLabel: 'رجوع',
        primaryIcon: Icons.arrow_back_rounded,
        onPrimary: () => Navigator.of(context).pop(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 300,
          child: MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_done) return;
              final code = capture.barcodes
                  .map((b) => b.rawValue ?? '')
                  .firstWhere((v) => v.isNotEmpty, orElse: () => '');
              if (code.isEmpty) return;
              _done = true;
              Navigator.of(context).pop(code.trim());
            },
          ),
        ),
      ),
    );
  }
}
