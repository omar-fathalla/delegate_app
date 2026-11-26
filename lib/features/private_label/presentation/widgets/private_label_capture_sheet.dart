import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_photo_pair.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

/// Camera helper tuned for shelf photos (compressed, back camera).
abstract final class PrivateLabelCamera {
  static final ImagePicker _picker = ImagePicker();

  static Future<String?> capture() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 72,
    );
    return file?.path;
  }
}

/// Parses prices typed with Arabic-Indic digits or a comma decimal separator.
double? parsePrivateLabelPrice(String raw) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final ch in raw.trim().split('')) {
    final idx = arabic.indexOf(ch);
    if (idx >= 0) {
      buffer.write(idx);
    } else if (ch == '٫' || ch == ',') {
      buffer.write('.');
    } else {
      buffer.write(ch);
    }
  }
  return double.tryParse(buffer.toString());
}

/// Quick-Flow capture form: both photos are already taken when this opens,
/// so the marketer only confirms the product, types the shelf price and saves.
class PrivateLabelCaptureSheet extends StatefulWidget {
  final PrivateLabelSheetLayout layout;
  final String initialProductPath;
  final String? initialPricePath;
  final List<String> branches;
  final String? initialBranch;
  final List<PrivateLabelProduct> products;
  final List<String> recentProductNames;
  final String organizationUID;
  final String companyUID;
  final String delegateUid;
  final String delegateName;
  final DateTime Function() clock;

  const PrivateLabelCaptureSheet({
    super.key,
    required this.layout,
    required this.initialProductPath,
    this.initialPricePath,
    required this.branches,
    this.initialBranch,
    required this.products,
    this.recentProductNames = const [],
    required this.organizationUID,
    required this.companyUID,
    required this.delegateUid,
    required this.delegateName,
    required this.clock,
  });

  @override
  State<PrivateLabelCaptureSheet> createState() => _PrivateLabelCaptureSheetState();
}

class _PrivateLabelCaptureSheetState extends State<PrivateLabelCaptureSheet> {
  late String _productPath = widget.initialProductPath;
  late String _pricePath = widget.initialPricePath ?? '';
  late String _branch = widget.initialBranch ?? (widget.branches.length == 1 ? widget.branches.first : '');
  late final List<PrivateLabelProduct> _catalogProducts = (widget.products.isNotEmpty
          ? widget.products
          : PrivateLabelProduct.defaultCatalog(widget.organizationUID))
      .where((p) => p.isActive)
      .toList();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  PrivateLabelProduct? _selectedProduct;
  String? _barcode;
  PrivateLabelStockStatus _stock = PrivateLabelStockStatus.available;

  @override
  void initState() {
    super.initState();
    _priceCtrl.addListener(() => setState(() {}));
    _branchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  void _selectProduct(PrivateLabelProduct p) {
    setState(() {
      _selectedProduct = p;
      _barcode = p.barcode;
    });
  }

  String get _effectiveBranch => widget.branches.isEmpty ? _branchCtrl.text.trim() : _branch;

  double? get _price => parsePrivateLabelPrice(_priceCtrl.text);

  bool get _isValid =>
      _productPath.isNotEmpty &&
      _pricePath.isNotEmpty &&
      _effectiveBranch.isNotEmpty &&
      _selectedProduct != null &&
      _selectedProduct!.name.trim().isNotEmpty &&
      (_price ?? 0) > 0;

  Future<void> _retake({required bool product}) async {
    final path = await PrivateLabelCamera.capture();
    if (path == null || !mounted) return;
    setState(() => product ? _productPath = path : _pricePath = path);
  }

  Future<void> _scanBarcode() async {
    final code = await showPrivateLabelSheet<String>(
      context: context,
      heightFactor: 0.75,
      builder: (ctx, layout) => _BarcodeScannerSheet(layout: layout),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final match = _catalogProducts.where((p) => p.barcode == code).firstOrNull;
    if (match != null) {
      _selectProduct(match);
    } else {
      setState(() => _barcode = code);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('الباركود $code غير مسجل في الكتالوج، اختار المنتج من القائمة.')),
      );
    }
  }

  void _save() {
    if (!_isValid) return;
    final product = _selectedProduct!;
    final draft = PrivateLabelAuditDraft(
      id: const Uuid().v4().replaceAll('-', ''),
      organizationUID: widget.organizationUID,
      companyUID: widget.companyUID,
      delegateUid: widget.delegateUid,
      delegateName: widget.delegateName,
      branchName: _effectiveBranch,
      productId: product.id,
      productName: product.name.trim(),
      barcode: _barcode ?? product.barcode,
      referencePrice: product.referencePrice,
      shelfPrice: _price!,
      stockStatus: _stock,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      productImagePath: _productPath,
      priceImagePath: _pricePath,
      capturedAt: widget.clock(),
    );
    Navigator.of(context).pop(draft);
  }

  InputDecoration _decoration(ColorScheme cs, {required String label, IconData? icon, Widget? suffix, String? suffixText, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      suffixIcon: suffix,
      suffixText: suffixText,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ref = _selectedProduct?.referencePrice;
    final price = _price;
    final mismatch = ref != null && price != null && (price - ref).abs() > PrivateLabelAudit.priceTolerance;

    final recentProducts = widget.recentProductNames
        .map((name) => _catalogProducts.where((p) => p.name == name).firstOrNull)
        .whereType<PrivateLabelProduct>()
        .toList();

    return PrivateLabelSheetFrame(
      layout: widget.layout,
      icon: Icons.add_a_photo_rounded,
      title: 'فحص منتج جديد',
      subtitle: 'راجع الصورتين واختار المنتج من الكتالوج واكتب سعر الرف',
      actions: PrivateLabelConnectedActions(
        primaryLabel: 'حفظ التوثيق',
        primaryIcon: Icons.check_rounded,
        onPrimary: _isValid ? _save : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _CaptureSlot(
                  label: 'صورة المنتج على الرف',
                  icon: Icons.storefront_rounded,
                  path: _productPath,
                  onTap: () => _retake(product: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CaptureSlot(
                  label: 'صورة بطاقة السعر',
                  icon: Icons.sell_rounded,
                  path: _pricePath,
                  onTap: () => _retake(product: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'الفرع'),
          const SizedBox(height: 6),
          if (widget.branches.isEmpty)
            TextField(
              controller: _branchCtrl,
              textInputAction: TextInputAction.next,
              decoration: _decoration(cs, label: 'اسم الفرع', icon: Icons.store_rounded),
            )
          else
            _BranchMenu(
              branches: widget.branches,
              selected: _branch,
              onSelected: (b) => setState(() => _branch = b),
            ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'المنتج (من الكتالوج)'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: PrivateLabelProductDropdownMenu(
                  products: _catalogProducts,
                  selectedProduct: _selectedProduct,
                  onSelected: _selectProduct,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                width: 44,
                child: IconButton.filledTonal(
                  tooltip: 'مسح الباركود',
                  onPressed: _scanBarcode,
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                ),
              ),
            ],
          ),
          if (recentProducts.isNotEmpty && _selectedProduct == null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: recentProducts
                  .take(6)
                  .map((p) => ActionChip(
                        avatar: const Icon(Icons.history_rounded, size: 16),
                        label: Text(p.name),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        onPressed: () => _selectProduct(p),
                      ))
                  .toList(),
            ),
          ],
          if (_selectedProduct != null) ...[
            const SizedBox(height: 8),
            _SelectedProductSummaryCard(
              product: _selectedProduct!,
              barcode: _barcode ?? _selectedProduct!.barcode,
            ),
          ] else if (_barcode != null) ...[
            const SizedBox(height: 6),
            Text(
              'الباركود: $_barcode',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          _sectionLabel(theme, 'سعر الرف'),
          const SizedBox(height: 6),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: _decoration(
              cs,
              label: 'السعر المكتوب على الرف',
              icon: Icons.payments_rounded,
              suffixText: 'ج.م',
            ),
          ),
          if (ref != null) ...[
            const SizedBox(height: 8),
            PrivateLabelAccentContainer(
              accent: mismatch ? cs.tertiary : cs.primary,
              child: Row(
                children: [
                  Icon(
                    mismatch ? Icons.price_change_rounded : Icons.verified_rounded,
                    size: 18,
                    color: mismatch ? cs.tertiary : cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mismatch
                          ? 'السعر الرسمي ${PrivateLabelLabels.price(ref)} — فيه فرق ${PrivateLabelLabels.price((price - ref).abs())}، هيتعلّم للمراجعة.'
                          : 'السعر الرسمي ${PrivateLabelLabels.price(ref)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _sectionLabel(theme, 'التواجد على الرف'),
          const SizedBox(height: 6),
          TashilConnectedButtonGroup<PrivateLabelStockStatus>(
            isScrollable: true,
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
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: _decoration(cs, label: 'ملاحظات (اختياري)', icon: Icons.notes_rounded),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      );
}

class _CaptureSlot extends StatelessWidget {
  final String label;
  final IconData icon;
  final String path;
  final VoidCallback onTap;

  const _CaptureSlot({
    required this.label,
    required this.icon,
    required this.path,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasPhoto = path.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 150,
              child: hasPhoto
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        PrivateLabelImage(path: path),
                        PositionedDirectional(
                          bottom: 8,
                          end: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cameraswitch_rounded, size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text('إعادة', style: theme.textTheme.labelSmall?.copyWith(color: cs.primary)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded, color: cs.primary, size: 30),
                        const SizedBox(height: 6),
                        Text('اضغط للتصوير', style: theme.textTheme.labelMedium?.copyWith(color: cs.primary)),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              hasPhoto ? Icons.check_circle_rounded : icon,
              size: 14,
              color: hasPhoto ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// M3 dropdown trigger (44dp) + menu, per the project's dropdown standard.
class _BranchMenu extends StatelessWidget {
  final List<String> branches;
  final String selected;
  final ValueChanged<String> onSelected;

  const _BranchMenu({
    required this.branches,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'اختيار الفرع',
      offset: const Offset(0, 48),
      color: cs.surfaceContainerHigh,
      elevation: 3,
      constraints: const BoxConstraints(maxHeight: 360, minWidth: 240),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => branches
          .map((b) => PopupMenuItem<String>(
                value: b,
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      Icons.store_rounded,
                      size: 18,
                      color: b == selected ? cs.primary : cs.onSurface,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b,
                        style: TextStyle(
                          fontWeight: b == selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (b == selected) Icon(Icons.check_rounded, size: 18, color: cs.primary),
                  ],
                ),
              ))
          .toList(),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.store_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected.isEmpty ? 'اختار الفرع' : selected,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: selected.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// M3 Dropdown Menu (44dp trigger + surfaceContainerHigh menu) for selecting a
/// Private Label product from the catalog instead of manual typing.
class PrivateLabelProductDropdownMenu extends StatelessWidget {
  final List<PrivateLabelProduct> products;
  final PrivateLabelProduct? selectedProduct;
  final ValueChanged<PrivateLabelProduct> onSelected;
  final String placeholder;

  const PrivateLabelProductDropdownMenu({
    super.key,
    required this.products,
    required this.selectedProduct,
    required this.onSelected,
    this.placeholder = 'اختار المنتج من الكتالوج',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = selectedProduct;
    final hasImage = selected?.imageUrl != null && selected!.imageUrl!.trim().isNotEmpty;

    return PopupMenuButton<PrivateLabelProduct>(
      tooltip: 'اختيار المنتج من الكتالوج',
      offset: const Offset(0, 48),
      color: cs.surfaceContainerHigh,
      elevation: 3,
      constraints: const BoxConstraints(maxHeight: 380, minWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => products.map((p) {
        final isSelected = selected != null && (p.id == selected.id || p.name == selected.name);
        final itemHasImage = p.imageUrl != null && p.imageUrl!.trim().isNotEmpty;
        return PopupMenuItem<PrivateLabelProduct>(
          value: p,
          height: 54,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: itemHasImage
                    ? PrivateLabelImage(path: p.imageUrl!)
                    : Icon(
                        Icons.inventory_2_rounded,
                        size: 18,
                        color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 13,
                        color: isSelected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (p.referencePrice != null)
                          'السعر الرسمي: ${PrivateLabelLabels.price(p.referencePrice!)}',
                        if (p.barcode != null && p.barcode!.isNotEmpty) p.barcode!,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_rounded, size: 18, color: cs.primary),
              ],
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected != null ? cs.primary.withValues(alpha: 0.6) : cs.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            if (hasImage)
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: PrivateLabelImage(path: selected.imageUrl!),
              )
            else
              Icon(Icons.inventory_2_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected == null ? placeholder : selected.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: selected == null ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
            ),
            if (selected?.referencePrice != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  PrivateLabelLabels.price(selected!.referencePrice!),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SelectedProductSummaryCard extends StatelessWidget {
  final PrivateLabelProduct product;
  final String? barcode;

  const _SelectedProductSummaryCard({
    required this.product,
    this.barcode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasImage = product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? PrivateLabelImage(path: product.imageUrl!)
                : Icon(Icons.inventory_2_rounded, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    if (product.referencePrice != null)
                      Text(
                        'السعر الرسمي: ${PrivateLabelLabels.price(product.referencePrice!)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (barcode != null && barcode!.isNotEmpty)
                      Text(
                        'باركود: $barcode',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeScannerSheet extends StatefulWidget {
  final PrivateLabelSheetLayout layout;

  const _BarcodeScannerSheet({required this.layout});

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
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
      subtitle: 'وجّه الكاميرا على الباركود',
      actions: PrivateLabelConnectedActions(
        primaryLabel: 'رجوع',
        primaryIcon: Icons.arrow_back_rounded,
        onPrimary: () => Navigator.of(context).pop(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 320,
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
