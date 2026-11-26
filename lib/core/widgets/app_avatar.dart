import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../storage/storage_media.dart';
import '../utils/image_url_helper.dart';
import 'storage_resolved_image.dart';

/// ويدجت موحد وآمن لعرض الصور الشخصية والأفاتار في التطبيق
/// يتعامل تلقائياً وبأمان تام مع أخطاء الروابط المنتهية أو غير المصرح بها (مثل 403 Forbidden و 404)
/// دون إلقاء استثناءات حمراء في كونسول التطبيق (Debug Console)، مع عرض الحرف الأول كبديل تلقائي
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackText;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Widget? badge;
  final IconData? fallbackIcon;

  /// Draws [fallbackText] in full. Callers that leave this false keep the
  /// first-character fallback, including every mobile avatar.
  final bool verbatimFallback;

  /// Share of the letter size an Arabic initial is lifted by (TAS-384).
  @visibleForTesting
  static const double arabicLift = 0.18;

  static final RegExp _arabic = RegExp(r'[\u0600-\u06FF]');

  const AppAvatar({
    super.key,
    this.imageUrl,
    required this.fallbackText,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
    this.badge,
    this.fallbackIcon,
    this.verbatimFallback = false,
  });

  AppAvatar _withImage(String? url) => AppAvatar(
        imageUrl: url,
        fallbackText: fallbackText,
        radius: radius,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        badge: badge,
        fallbackIcon: fallbackIcon,
        verbatimFallback: verbatimFallback,
      );

  @override
  Widget build(BuildContext context) {
    if (radius <= 0) return const SizedBox.shrink();
    // TAS-331: a stored Storage path is turned into a URL through the
    // Storage rules; the initial shows while it resolves or when denied.
    final stored = imageUrl?.trim() ?? '';
    if (StorageMediaRef.isStoragePath(stored)) {
      final placeholder = _withImage(null);
      return StorageResolvedImage(
        pathOrUrl: stored,
        builder: (context, url) => _withImage(url),
        loading: placeholder,
        error: placeholder,
      );
    }
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.primaryContainer;
    final fg = foregroundColor ?? theme.colorScheme.onPrimaryContainer;
    final size = radius * 2;
    final trimmed = fallbackText.trim();
    final initial = verbatimFallback
        ? (trimmed.isNotEmpty ? trimmed : '؟')
        : (trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '؟');

    final letterSize = verbatimFallback ? radius * 0.7 : radius * 0.85;

    Widget fallbackWidget() {
      return Container(
        width: size,
        height: size,
        color: bg,
        alignment: Alignment.center,
        child: fallbackIcon != null
            ? Icon(
                fallbackIcon,
                color: fg,
                size: radius * 1.15,
              )
            // TAS-384: Cairo puts the baseline low (large descent), so an
            // Arabic letter sat under the centre. Height 1 with even leading
            // centres the line box; Arabic initials are then lifted by a
            // share of the font size so the letter itself looks centred.
            : Transform.translate(
                offset: Offset(
                  0,
                  _arabic.hasMatch(initial) ? -letterSize * arabicLift : 0,
                ),
                child: Text(
                  initial,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.bold,
                    fontSize: letterSize,
                    height: 1,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
      );
    }

    final cleanUrl = imageUrl?.trim();
    final hasUrl = cleanUrl != null &&
        cleanUrl.isNotEmpty &&
        (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://'));

    Widget avatarContent;
    if (!hasUrl) {
      avatarContent = fallbackWidget();
    } else if (kIsWeb) {
      // On Flutter Web CanvasKit, cross-origin images without CORS headers get blocked.
      // ImageUrlHelper routes Firebase Storage URLs through a high-speed CORS proxy.
      final webUrl = ImageUrlHelper.getWebSafeUrl(
        cleanUrl,
        width: (size * 2).toInt(),
        height: (size * 2).toInt(),
      );

      avatarContent = Image.network(
        webUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: size,
            height: size,
            color: bg,
            alignment: Alignment.center,
            child: SizedBox(
              width: radius * 0.65,
              height: radius * 0.65,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg.withValues(alpha: 0.5),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          // If proxy failed, attempt direct URL or fallback to initial
          return Image.network(
            cleanUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallbackWidget(),
          );
        },
      );
    } else {
      final pixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
      final cachePx = (size * pixelRatio).round().clamp(32, 256);
      avatarContent = CachedNetworkImage(
        imageUrl: cleanUrl,
        width: size,
        height: size,
        memCacheWidth: cachePx,
        memCacheHeight: cachePx,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (context, url) => Container(
          width: size,
          height: size,
          color: bg,
          alignment: Alignment.center,
          child: SizedBox(
            width: radius * 0.65,
            height: radius * 0.65,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: fg.withValues(alpha: 0.5),
            ),
          ),
        ),
        errorListener: (error) {
          // التعامل بمرونة مع أخطاء الروابط المنتهية (403 أو 404 أو انقطاع النت)
          // يمنع نهائياً تسجيل استثناء غير معالج في DevTools أو كونسول الفحص
        },
        errorWidget: (context, url, error) {
          // التعامل بمرونة مع أخطاء الروابط المنتهية (403 أو 404 أو انقطاع النت)
          // يمنع نهائياً طباعة خطأ HttpException 403 باللون الأحمر في كونسول الفحص
          return fallbackWidget();
        },
      );
    }

    final circularAvatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: avatarContent,
      ),
    );

    if (badge == null) {
      return circularAvatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        circularAvatar,
        Positioned(
          bottom: -1,
          right: -1,
          child: badge!,
        ),
      ],
    );
  }
}
