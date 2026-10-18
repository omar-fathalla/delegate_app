import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Displays a network URL or a local captured image (web-safe: `blob:` URLs).
class PrivateLabelImage extends StatelessWidget {
  final String path;
  final bool isThumbnail;
  final BoxFit fit;

  const PrivateLabelImage({
    super.key,
    required this.path,
    this.isThumbnail = false,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => Icon(
          Icons.image_not_supported_rounded,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    if (kIsWeb && (path.startsWith('blob:') || path.startsWith('data:'))) {
      return Image.network(
        path,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => Icon(
          Icons.image_not_supported_rounded,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return AppPhotoImage(photoUrl: path, isThumbnail: isThumbnail, fit: fit);
  }
}

/// Two photos side by side (product + price tag). Tap either to zoom full-screen.
class PrivateLabelPhotoPair extends StatelessWidget {
  final String productPhoto;
  final String pricePhoto;
  final double height;
  final bool isThumbnail;

  const PrivateLabelPhotoPair({
    super.key,
    required this.productPhoto,
    required this.pricePhoto,
    this.height = 180,
    this.isThumbnail = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      if (productPhoto.isNotEmpty)
        PrivateLabelPhotoItem(
          path: productPhoto,
          label: 'المنتج على الرف',
          heroTag: 'pl_product_$productPhoto',
        ),
      if (pricePhoto.isNotEmpty)
        PrivateLabelPhotoItem(
          path: pricePhoto,
          label: 'بطاقة السعر',
          heroTag: 'pl_price_$pricePhoto',
        ),
    ];

    return Row(
      children: [
        Expanded(
          child: _PhotoTile(
            label: 'المنتج على الرف',
            icon: Icons.storefront_rounded,
            path: productPhoto,
            height: height,
            isThumbnail: isThumbnail,
            heroTag: 'pl_product_$productPhoto',
            onTap: productPhoto.isEmpty
                ? null
                : () => PrivateLabelZoomViewer.openGallery(context, items: items, initialIndex: 0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PhotoTile(
            label: 'بطاقة السعر',
            icon: Icons.sell_rounded,
            path: pricePhoto,
            height: height,
            isThumbnail: isThumbnail,
            heroTag: 'pl_price_$pricePhoto',
            onTap: pricePhoto.isEmpty
                ? null
                : () => PrivateLabelZoomViewer.openGallery(
                      context,
                      items: items,
                      initialIndex: productPhoto.isNotEmpty ? 1 : 0,
                    ),
          ),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final String path;
  final double height;
  final bool isThumbnail;
  final String heroTag;
  final VoidCallback? onTap;

  const _PhotoTile({
    required this.label,
    required this.icon,
    required this.path,
    required this.height,
    required this.isThumbnail,
    required this.heroTag,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: path.isEmpty
                  ? Icon(Icons.image_not_supported_rounded, color: cs.outline)
                  : Hero(
                      tag: heroTag,
                      child: PrivateLabelImage(path: path, isThumbnail: isThumbnail),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (path.isNotEmpty) Icon(Icons.zoom_in_rounded, size: 14, color: cs.outline),
          ],
        ),
      ],
    );
  }
}

class PrivateLabelPhotoItem {
  final String path;
  final String label;
  final String heroTag;

  const PrivateLabelPhotoItem({
    required this.path,
    required this.label,
    required this.heroTag,
  });
}

/// Full-screen pinch-to-zoom viewer with gallery swiping (used to read small price tags).
class PrivateLabelZoomViewer extends StatefulWidget {
  final List<PrivateLabelPhotoItem> items;
  final int initialIndex;

  const PrivateLabelZoomViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  static Future<void> open(BuildContext context, String path, String heroTag, String title) {
    return openGallery(
      context,
      items: [PrivateLabelPhotoItem(path: path, label: title, heroTag: heroTag)],
      initialIndex: 0,
    );
  }

  static Future<void> openGallery(
    BuildContext context, {
    required List<PrivateLabelPhotoItem> items,
    int initialIndex = 0,
  }) {
    if (items.isEmpty) return Future.value();
    final reduce = MediaQuery.of(context).disableAnimations;
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: reduce ? Duration.zero : AppMotionDurations.medium4,
        reverseTransitionDuration: reduce ? Duration.zero : AppMotionDurations.short4,
        pageBuilder: (_, _, _) => PrivateLabelZoomViewer(items: items, initialIndex: initialIndex),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AppMotionCurves.standardDefaultEffects,
            reverseCurve: AppMotionCurves.standardAccelerate,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  State<PrivateLabelZoomViewer> createState() => _PrivateLabelZoomViewerState();
}

class _PrivateLabelZoomViewerState extends State<PrivateLabelZoomViewer> {
  late final PageController _pageController = PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.items[_currentIndex];
    final count = widget.items.length;
    final titleText = count > 1
        ? '${currentItem.label} (${_currentIndex + 1}/$count)'
        : currentItem.label;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(titleText),
      ),
      body: widget.items.length == 1
          ? InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: Hero(
                  tag: currentItem.heroTag,
                  child: PrivateLabelImage(path: currentItem.path, fit: BoxFit.contain),
                ),
              ),
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (context, i) {
                final item = widget.items[i];
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: Hero(
                      tag: item.heroTag,
                      child: PrivateLabelImage(path: item.path, fit: BoxFit.contain),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

