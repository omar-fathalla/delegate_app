import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_review_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_product_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// صفحة الكتالوج (Private Label Catalog Screen)
/// السيستم المخصص لإدخال وإدارة منتجات العلامة الخاصة (الاسم، السعر المعتمد، الباركود، والصورة)
/// التي تظهر تلقائياً في الـ Dropdown Menu أثناء تصوير الفروع وفي فلاتر المراجعة.
/// لمستخدمي تسويق الفروع (`UserRole.marketing`) تعمل الصفحة بوضع العرض فقط (للنظر فقط).
class PrivateLabelCatalogScreen extends StatelessWidget {
  final Delegate delegate;
  final bool? readOnly;

  const PrivateLabelCatalogScreen({
    super.key,
    required this.delegate,
    this.readOnly,
  });

  /// يحدد ما إذا كان المستخدم يملك صلاحية الإضافة والتعديل في الكتالوج.
  /// مستخدم تسويق الفروع (`UserRole.marketing`) يكون للنظر فقط (`false`).
  static bool canEditCatalog(Delegate delegate) {
    return delegate.role == UserRole.superAdmin ||
        delegate.role == UserRole.marketingPromotion ||
        delegate.role == UserRole.branchesMarketingManager ||
        delegate.role == UserRole.organizationAdmin;
  }

  bool get isReadOnly => (readOnly ?? false) || !canEditCatalog(delegate);

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PrivateLabelReviewBloc>(
      create: (_) => sl<PrivateLabelReviewBloc>()
        ..add(PrivateLabelReviewStarted(
          organizationUID: delegate.organizationUID,
          companyUID: delegate.companyUID,
          reviewerUid: delegate.uid,
          reviewerName: delegate.fullName,
        )),
      child: _CatalogView(
        delegate: delegate,
        readOnly: isReadOnly,
      ),
    );
  }
}

class _CatalogView extends StatefulWidget {
  final Delegate delegate;
  final bool readOnly;

  const _CatalogView({
    required this.delegate,
    required this.readOnly,
  });

  @override
  State<_CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<_CatalogView> {
  final _searchCtrl = TextEditingController();
  String? _selectedCategory;

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

  Future<void> _openProductSheet([PrivateLabelProduct? product]) async {
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
    final effectiveOrg = widget.delegate.organizationUID.trim().isNotEmpty
        ? widget.delegate.organizationUID.trim()
        : 'PiioBFgxaHAeuRdjlDgj';
    final saved = await showPrivateLabelProductSheet(
      context: context,
      organizationUID: effectiveOrg,
      product: product,
    );
    if (saved != null) {
      bloc.add(PrivateLabelReviewProductSaved(saved));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BlocListener<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      listenWhen: (p, c) => c.feedback != null && p.feedback?.id != c.feedback?.id,
      listener: (context, state) {
        final f = state.feedback!;
        f.isError
            ? AppSnackBar.showError(context, f.message)
            : AppSnackBar.showSuccess(context, f.message);
      },
      child: BlocBuilder<PrivateLabelReviewBloc, PrivateLabelReviewState>(
        builder: (context, state) {
          final categories = state.products
              .map((p) => (p.category ?? '').trim())
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final q = _searchCtrl.text.trim().toLowerCase();
          final filtered = state.products.where((p) {
            if (_selectedCategory != null &&
                _selectedCategory!.isNotEmpty &&
                (p.category ?? '').trim() != _selectedCategory) {
              return false;
            }
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q) ||
                (p.barcode ?? '').toLowerCase().contains(q) ||
                (p.category ?? '').toLowerCase().contains(q);
          }).toList();

          final activeCount = state.products.where((p) => p.isActive).length;

          return Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('الكتالوج (Products Catalog)'),
                  Text(
                    widget.readOnly
                        ? 'استعراض منتجات البرايفت ليبل وأسعارها المعتمدة'
                        : 'منتجات العلامة الخاصة وأسعارها المعتمدة',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
              centerTitle: false,
              actions: [
                if (state.isSavingProduct)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                if (!widget.readOnly)
                  IconButton(
                    tooltip: 'إضافة منتج جديد',
                    icon: const Icon(Icons.add_box_rounded),
                    onPressed: () => _openProductSheet(),
                  ),
                IconButton(
                  tooltip: 'تحديث الكتالوج',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => context
                      .read<PrivateLabelReviewBloc>()
                      .add(const PrivateLabelReviewRefreshRequested()),
                ),
                const SizedBox(width: 4),
              ],
            ),
            floatingActionButton: widget.readOnly
                ? null
                : FloatingActionButton.extended(
                    heroTag: 'pl_catalog_add_fab',
                    onPressed: state.isSavingProduct ? null : () => _openProductSheet(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة منتج للكتالوج'),
                  ),
            body: RefreshIndicator(
              onRefresh: () async {
                final bloc = context.read<PrivateLabelReviewBloc>()
                  ..add(const PrivateLabelReviewRefreshRequested());
                await bloc.stream
                    .firstWhere((s) => s.status != PrivateLabelReviewStatusView.loading)
                    .timeout(const Duration(seconds: 15), onTimeout: () => bloc.state);
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 768;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1050),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Header Banner
                            _buildCatalogBanner(
                              context,
                              cs,
                              totalCount: state.products.length,
                              activeCount: activeCount,
                            ),
                            const SizedBox(height: 16),

                            // 2. Search & Category Filter Row
                            _buildSearchAndFilterToolbar(
                              context,
                              cs,
                              categories: categories,
                              desktop: desktop,
                            ),
                            const SizedBox(height: 16),

                            // 3. Products Grid / List
                            if (state.status == PrivateLabelReviewStatusView.loading &&
                                state.products.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 48),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (filtered.isEmpty)
                              _buildEmptyState(context, cs, state.products.isEmpty)
                            else if (desktop)
                              LayoutBuilder(
                                builder: (context, c) {
                                  final itemWidth = (c.maxWidth - 12) / 2;
                                  return Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      for (final p in filtered)
                                        SizedBox(
                                          width: itemWidth,
                                          child: PrivateLabelCatalogProductTile(
                                            product: p,
                                            readOnly: widget.readOnly,
                                            onTap: () => _openProductSheet(p),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              )
                            else
                              Column(
                                children: [
                                  for (final p in filtered) ...[
                                    PrivateLabelCatalogProductTile(
                                      product: p,
                                      readOnly: widget.readOnly,
                                      onTap: () => _openProductSheet(p),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCatalogBanner(
    BuildContext context,
    ColorScheme cs, {
    required int totalCount,
    required int activeCount,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'كتالوج منتجات البرايفت ليبل',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.readOnly
                          ? 'استعراض منتجات البرايفت ليبل وأسعارها المعتمدة والباركود والأقسام الخاصة بها (وضع العرض فقط).'
                          : 'أي منتج يتم إضافته أو تعديله هنا (بالاسم، السعر، الباركود، والصورة) يظهر فوراً في القائمة المنسدلة (Dropdown Menu) عند التصوير وفي فلاتر الفروع.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statBadge(
                cs: cs,
                icon: Icons.inventory_2_rounded,
                label: 'إجمالي المنتجات: $totalCount',
              ),
              _statBadge(
                cs: cs,
                icon: Icons.check_circle_rounded,
                label: 'نشط في القائمة المنسدلة: $activeCount',
              ),
              if (widget.readOnly)
                _statBadge(
                  cs: cs,
                  icon: Icons.visibility_rounded,
                  label: 'وضع العرض فقط',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBadge({
    required ColorScheme cs,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterToolbar(
    BuildContext context,
    ColorScheme cs, {
    required List<String> categories,
    required bool desktop,
  }) {
    final theme = Theme.of(context);
    final searchField = SizedBox(
      height: 44,
      child: TextField(
        controller: _searchCtrl,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.normal,
          color: cs.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'ابحث باسم المنتج أو الباركود أو القسم...',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: cs.onSurfaceVariant.withValues(alpha: 0.65),
          ),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => _searchCtrl.clear(),
                )
              : null,
          filled: true,
          fillColor: cs.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
        ),
      ),
    );

    final categoryDropdown = Theme(
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
        tooltip: 'فلترة بالقسم',
        offset: const Offset(0, 48),
        onSelected: (cat) => setState(() => _selectedCategory = cat),
        itemBuilder: (context) => [
          PopupMenuItem<String?>(
            value: null,
            child: Row(
              children: [
                Icon(Icons.category_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('كل الأقسام', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (_selectedCategory == null)
                  Icon(Icons.check_rounded, size: 18, color: cs.primary),
              ],
            ),
          ),
          if (categories.isNotEmpty) const PopupMenuDivider(),
          for (final c in categories)
            PopupMenuItem<String?>(
              value: c,
              child: Row(
                children: [
                  Icon(Icons.label_outline_rounded, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c,
                      style: TextStyle(
                        fontWeight: _selectedCategory == c ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (_selectedCategory == c)
                    Icon(Icons.check_rounded, size: 18, color: cs.primary),
                ],
              ),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _selectedCategory != null
                ? cs.primary.withValues(alpha: 0.08)
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selectedCategory != null
                  ? cs.primary.withValues(alpha: 0.5)
                  : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.category_rounded,
                size: 18,
                color: _selectedCategory != null ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _selectedCategory ?? 'كل الأقسام',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _selectedCategory != null ? cs.primary : cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.expand_more_rounded, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );

    if (desktop) {
      return Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 12),
          SizedBox(width: 220, child: categoryDropdown),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField,
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 10),
          categoryDropdown,
        ],
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme cs, bool isCatalogEmpty) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: cs.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            isCatalogEmpty ? 'لا توجد منتجات مسجلة في الكتالوج حالياً' : 'لا توجد منتجات مطابقة للبحث',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isCatalogEmpty
                ? (widget.readOnly
                    ? 'لم يتم تسجيل منتجات في الكتالوج من قِبل إدارة التسويق بعد.'
                    : 'اضغط على "إضافة منتج للكتالوج" لإدخال اسم المنتج والسعر والباركود والصورة.')
                : 'جرّب البحث بكلمة أخرى أو تغيير فلتر القسم.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
