import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/design/color_schemes.dart';
import '../../../core/design/tokens.dart';

/// Content-based colour: a product card coloured from its photo. The
/// "photos" are drawn here so the playground needs no image assets.
class ContentColorDemo extends StatefulWidget {
  const ContentColorDemo({super.key});

  @override
  State<ContentColorDemo> createState() => _ContentColorDemoState();
}

class _Product {
  const _Product(this.name, this.price, this.colors);
  final String name;
  final String price;
  final List<Color> colors;
}

const _products = [
  _Product('عصير برتقال 1 لتر', '45.00 ج.م', [
    Color(0xFFFF9800),
    Color(0xFFFFC107),
    Color(0xFF4CAF50),
  ]),
  _Product('توت مجمد 400 جم', '120.00 ج.م', [
    Color(0xFF4A148C),
    Color(0xFF880E4F),
    Color(0xFF1A237E),
  ]),
  _Product('مياه معدنية 1.5 لتر', '10.00 ج.م', [
    Color(0xFF0288D1),
    Color(0xFF4FC3F7),
    Color(0xFFE1F5FE),
  ]),
];

/// Draws a simple "product photo" (overlapping circles) as a PNG.
Future<ImageProvider> _photo(List<Color> colors) async {
  const size = 96.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, size, size),
    Paint()..color = colors.last,
  );
  canvas.drawCircle(const Offset(40, 44), 34, Paint()..color = colors.first);
  canvas.drawCircle(const Offset(70, 66), 20, Paint()..color = colors[1]);
  final image = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return MemoryImage(Uint8List.view(bytes!.buffer));
}

class _ContentColorDemoState extends State<ContentColorDemo> {
  var _index = 0;
  final _photos = <int, Future<ImageProvider>>{};

  Future<ImageProvider> _photoFor(int i) =>
      _photos[i] ??= _photo(_products[i].colors);

  @override
  Widget build(BuildContext context) {
    final p = _products[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: TashilSpacing.sm,
          children: [
            for (final (i, x) in _products.indexed)
              FilterChip(
                label: Text(x.name.split(' ').first),
                selected: i == _index,
                onSelected: (_) => setState(() => _index = i),
              ),
          ],
        ),
        const SizedBox(height: TashilSpacing.md),
        FutureBuilder(
          future: _photoFor(_index),
          builder: (context, snap) {
            final image = snap.data;
            final card = _ProductCard(product: p, image: image);
            return image == null
                ? card
                : ContentColorScope(image: image, child: card);
          },
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.image});

  final _Product product;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: s.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(TashilRadius.medium),
              child: SizedBox.square(
                dimension: 72,
                child: image == null
                    ? ColoredBox(color: s.surfaceContainerHighest)
                    : Image(image: image!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: TashilSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: text.titleMedium?.copyWith(
                      color: s.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    product.price,
                    style: text.bodyMedium?.copyWith(
                      color: s.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.sm),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('أضف للسلة'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
