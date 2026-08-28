import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/photo_cache_manager.dart';
import 'app_loading_indicator.dart';

class AppPhotoImage extends StatefulWidget {
  final String photoUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool isThumbnail;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;

  const AppPhotoImage({
    super.key,
    required this.photoUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.isThumbnail = false,
    this.borderRadius,
    this.errorWidget,
  });

  @override
  State<AppPhotoImage> createState() => _AppPhotoImageState();
}

class _AppPhotoImageState extends State<AppPhotoImage> {
  File? _resolvedLocalFile;
  bool _isCheckingLocal = false;

  @override
  void initState() {
    super.initState();
    _checkLocalFile();
  }

  @override
  void didUpdateWidget(covariant AppPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _checkLocalFile();
    }
  }

  Future<void> _checkLocalFile() async {
    if (widget.photoUrl.startsWith('http://') || widget.photoUrl.startsWith('https://')) {
      return;
    }

    setState(() {
      _isCheckingLocal = true;
    });

    final file = await PhotoCacheManager.resolveLocalPhotoFile(widget.photoUrl);
    if (mounted) {
      setState(() {
        _resolvedLocalFile = file;
        _isCheckingLocal = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget content;
    final isNetwork = widget.photoUrl.startsWith('http://') || widget.photoUrl.startsWith('https://');

    if (isNetwork) {
      content = CachedNetworkImage(
        imageUrl: widget.photoUrl,
        cacheManager: PhotoCacheManager.instance,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: widget.isThumbnail ? 200 : null,
        memCacheHeight: widget.isThumbnail ? 200 : null,
        maxHeightDiskCache: widget.isThumbnail ? 400 : 1800,
        maxWidthDiskCache: widget.isThumbnail ? 400 : 1800,
        placeholder: (context, url) => Center(
          child: AppLoadingIndicator(
            size: widget.isThumbnail ? 16 : 28,
            color: colorScheme.primary,
            style: AppLoadingStyle.threeArchedCircle,
          ),
        ),
        errorWidget: (context, url, error) {
          // Fallback to basic Image.network in case custom cache manager had a transient issue
          return Image.network(
            widget.photoUrl,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: AppLoadingIndicator(
                  size: widget.isThumbnail ? 16 : 28,
                  color: colorScheme.primary,
                  style: AppLoadingStyle.threeArchedCircle,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                widget.errorWidget ?? _defaultErrorWidget(colorScheme),
          );
        },
      );
    } else {
      if (_isCheckingLocal) {
        content = Center(
          child: AppLoadingIndicator(
            size: widget.isThumbnail ? 16 : 28,
            color: colorScheme.primary,
            style: AppLoadingStyle.threeArchedCircle,
          ),
        );
      } else if (_resolvedLocalFile != null && _resolvedLocalFile!.existsSync()) {
        content = Image.file(
          _resolvedLocalFile!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) =>
              widget.errorWidget ?? _defaultErrorWidget(colorScheme),
        );
      } else {
        content = widget.errorWidget ?? _defaultErrorWidget(colorScheme);
      }
    }

    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return content;
  }

  Widget _defaultErrorWidget(ColorScheme colorScheme) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: colorScheme.outline.withValues(alpha: 0.6),
          size: widget.isThumbnail ? 22 : 48,
        ),
      ),
    );
  }
}
