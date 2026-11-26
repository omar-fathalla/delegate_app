import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import '../services/photo_cache_manager.dart';
import '../storage/storage_media.dart';
import '../utils/image_url_helper.dart';
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

  /// TAS-42: download URL for a Storage path (resolved at read time).
  String? _resolvedRemoteUrl;

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
    if ((kIsWeb && !StorageMediaRef.isStoragePath(widget.photoUrl)) ||
        widget.photoUrl.startsWith('http://') ||
        widget.photoUrl.startsWith('https://') ||
        widget.photoUrl.startsWith('assets/')) {
      return;
    }

    final requested = widget.photoUrl;
    final cached = StorageMediaRef.isStoragePath(requested)
        ? StorageMediaResolver.instance.cachedUrl(requested)
        : null;
    setState(() {
      _resolvedLocalFile = null;
      _resolvedRemoteUrl = cached;
      _isCheckingLocal = cached == null;
    });
    if (cached != null) return;

    final file =
        kIsWeb ? null : await PhotoCacheManager.resolveLocalPhotoFile(requested);
    String? remote;
    if ((file == null || !file.existsSync()) &&
        StorageMediaRef.isStoragePath(requested)) {
      remote = await StorageMediaResolver.instance.tryResolve(requested);
    }
    if (mounted && widget.photoUrl == requested) {
      setState(() {
        _resolvedLocalFile = file;
        _resolvedRemoteUrl = remote;
        _isCheckingLocal = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget content;
    final isAsset = widget.photoUrl.startsWith('assets/');
    final directNetwork = widget.photoUrl.startsWith('http://') || widget.photoUrl.startsWith('https://');
    final isNetwork = directNetwork || _resolvedRemoteUrl != null;
    final networkUrl = directNetwork ? widget.photoUrl : (_resolvedRemoteUrl ?? widget.photoUrl);
    // A Storage path is a stable cache key; its download URL may change.
    final cacheKey = directNetwork ? null : widget.photoUrl;

    if (isAsset) {
      content = Image.asset(
        widget.photoUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) =>
            widget.errorWidget ?? _defaultErrorWidget(colorScheme),
      );
    } else if (isNetwork) {
      if (kIsWeb) {
        final webUrl = ImageUrlHelper.getWebSafeUrl(
          networkUrl,
          width: widget.isThumbnail ? 400 : 1800,
        );
        content = Image.network(
          webUrl,
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
          errorBuilder: (context, error, stackTrace) => Image.network(
            networkUrl,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (c, e, s) =>
                widget.errorWidget ?? _defaultErrorWidget(colorScheme),
          ),
        );
      } else {
        content = CachedNetworkImage(
        imageUrl: networkUrl,
        cacheKey: cacheKey,
        cacheManager: PhotoCacheManager.instance,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: widget.isThumbnail ? 350 : null,
        memCacheHeight: widget.isThumbnail ? 350 : null,
        maxHeightDiskCache: widget.isThumbnail ? 600 : 1800,
        maxWidthDiskCache: widget.isThumbnail ? 600 : 1800,
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
            networkUrl,
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
      }
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
