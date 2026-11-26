// Sample widgets for the playground demos only (from m3-kit pos_widgets.dart,
// the ERP's product/cart composites). Not part of the app's design system:
// do not import them from app screens (docs/design/README.md).
import 'package:material_ui/material_ui.dart';

import '../../core/design/money.dart';
import '../../core/design/tokens.dart';

/// Money shown with tabular (fixed-width) digits so columns line up.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.piastres, {
    super.key,
    this.style,
    this.showCurrency = true,
  });

  final int piastres;
  final TextStyle? style;
  final bool showCurrency;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text(
      showCurrency ? Money.format(piastres) : Money.amount(piastres),
      style: base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      // Keep "1,250.50 ج.م" as one LTR run inside RTL text.
      textDirection: TextDirection.ltr,
    );
  }
}

/// Stock level label: normal, low (<= min) or out (<= 0).
///
/// Not a chip: M3 chips are interactive, this only shows a state.
class StockBadge extends StatelessWidget {
  const StockBadge({
    super.key,
    required this.quantity,
    required this.minStock,
    this.unit = '',
  });

  final double quantity;
  final double minStock;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sem = TashilSemanticColors.of(context);
    final (Color bg, Color fg) = quantity <= 0
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : quantity <= minStock
        ? (sem.warningContainer, sem.onWarningContainer)
        : (sem.successContainer, sem.onSuccessContainer);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TashilSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TashilRadius.small),
      ),
      child: Text(
        '${Money.qty(quantity)} $unit'.trim(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

/// Sync state of a record, mirrors `SyncStatus` in the database.
enum SyncState { synced, pending, failed }

/// Read-only sync state: icon + text. Not a chip, because M3 chips are
/// interactive (m3.material.io/components/chips/guidelines).
class SyncStatusLabel extends StatelessWidget {
  const SyncStatusLabel(this.state, {super.key});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sem = TashilSemanticColors.of(context);
    final (IconData icon, String label, Color color) = switch (state) {
      SyncState.synced => (
        Icons.cloud_done_outlined,
        'تمت المزامنة',
        sem.success,
      ),
      SyncState.pending => (
        Icons.cloud_upload_outlined,
        'في الانتظار',
        sem.warning,
      ),
      SyncState.failed => (Icons.cloud_off_outlined, 'فشلت', scheme.error),
    };
    return Semantics(
      label: 'المزامنة: $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: TashilSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Product row used in search results and the product list.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.name,
    required this.pricePiastres,
    required this.stock,
    required this.minStock,
    this.unit = '',
    this.barcode,
    this.onTap,
    this.onAdd,
  });

  final String name;
  final int pricePiastres;
  final double stock;
  final double minStock;
  final String unit;
  final String? barcode;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      minVerticalPadding: TashilSpacing.md,
      leading: Container(
        width: TashilSizes.thumbnail,
        height: TashilSizes.thumbnail,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(TashilRadius.medium),
        ),
        child: Text(
          name.characters.first,
          style: text.titleLarge?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Wrap, not Row: price + badge must fit on a 360dp screen.
      subtitle: Wrap(
        spacing: TashilSpacing.sm,
        runSpacing: TashilSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          MoneyText(pricePiastres, style: text.bodyMedium),
          StockBadge(quantity: stock, minStock: minStock, unit: unit),
        ],
      ),
      trailing: onAdd == null
          ? null
          : IconButton.filledTonal(
              tooltip: 'إضافة للسلة',
              onPressed: onAdd,
              icon: const Icon(Icons.add_shopping_cart),
            ),
    );
  }
}

/// − qty + control. Min 1; long quantities are typed on the keypad instead.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.quantity,
    required this.onChanged,
  });

  final double quantity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(TashilRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'زيادة',
            onPressed: () => onChanged(quantity + 1),
            icon: const Icon(Icons.add),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 32),
            child: Text(
              Money.qty(quantity),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'تقليل',
            onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
            icon: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }
}

/// One line in the POS cart. Swipe to remove.
class CartLine extends StatelessWidget {
  const CartLine({
    super.key,
    required this.name,
    required this.unitPricePiastres,
    required this.quantity,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final String name;
  final int unitPricePiastres;
  final double quantity;
  final ValueChanged<double> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = (unitPricePiastres * quantity).round();
    return Dismissible(
      key: ValueKey(name),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        color: scheme.errorContainer,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: TashilSpacing.xl),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TashilSpacing.page,
          vertical: TashilSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  MoneyText(
                    unitPricePiastres,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.xs),
                  MoneyText(total, style: text.titleMedium),
                ],
              ),
            ),
            QtyStepper(quantity: quantity, onChanged: onQuantityChanged),
          ],
        ),
      ),
    );
  }
}

/// Bottom bar on the POS screen: total + pay.
class CheckoutBar extends StatelessWidget {
  const CheckoutBar({
    super.key,
    required this.totalPiastres,
    required this.itemCount,
    required this.onPay,
  });

  final int totalPiastres;
  final int itemCount;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$itemCount صنف', style: text.labelMedium),
                    MoneyText(totalPiastres, style: text.headlineSmall),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(140, TashilSizes.posButtonHeight),
                ),
                onPressed: onPay,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('دفع'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keys emitted by [NumericKeypad].
sealed class KeypadKey {
  const KeypadKey();
}

class DigitKey extends KeypadKey {
  const DigitKey(this.value);
  final String value; // '0'-'9', '00' or '.'
}

class BackspaceKey extends KeypadKey {
  const BackspaceKey();
}

/// Calculator-style keypad for amounts and quantities.
///
/// Always laid out left-to-right (7 8 9 on top) even in RTL, matching every
/// physical keypad and calculator the cashier already knows.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.onKey,
    this.allowDecimal = true,
  });

  final ValueChanged<KeypadKey> onKey;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      [allowDecimal ? '.' : '00', '0', '⌫'],
    ];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TashilSpacing.xs),
              child: Row(
                children: [
                  for (final k in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: TashilSpacing.xs,
                        ),
                        child: _Key(
                          label: k,
                          onTap: () => onKey(
                            k == '⌫' ? const BackspaceKey() : DigitKey(k),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBack = label == '⌫';
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(TashilSizes.keypadKey),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TashilRadius.large),
      ),
      textStyle: Theme.of(context).textTheme.headlineSmall,
    );
    return isBack
        ? FilledButton.tonal(
            style: style,
            onPressed: onTap,
            child: const Icon(Icons.backspace_outlined, semanticLabel: 'مسح'),
          )
        : FilledButton.tonal(
            style: style,
            onPressed: onTap,
            child: Text(label),
          );
  }
}

/// Centered placeholder for empty lists (no products, empty cart, …).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(TashilSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: TashilSpacing.md),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: TashilSpacing.xs),
            Text(
              message!,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: TashilSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
