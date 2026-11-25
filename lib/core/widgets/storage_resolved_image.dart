import 'package:flutter/material.dart';

import '../storage/storage_media.dart';

/// TAS-42: builds [builder] with a displayable URL for a stored value that
/// may be a Storage path (resolved through the rules at read time) or an
/// old download URL (used as is).
class StorageResolvedImage extends StatefulWidget {
  const StorageResolvedImage({
    super.key,
    required this.pathOrUrl,
    required this.builder,
    this.loading,
    this.error,
    this.resolver,
  });

  /// TAS-331: [builder] right away for a value that is not a Storage path
  /// (URLs, local files, assets: no extra frame), [StorageResolvedImage]
  /// for a path.
  static Widget wrap({
    Key? key,
    required String pathOrUrl,
    required Widget Function(BuildContext context, String url) builder,
    Widget? loading,
    Widget? error,
  }) {
    if (!StorageMediaRef.isStoragePath(pathOrUrl)) {
      return Builder(key: key, builder: (context) => builder(context, pathOrUrl));
    }
    return StorageResolvedImage(
      key: key,
      pathOrUrl: pathOrUrl,
      builder: builder,
      loading: loading,
      error: error,
    );
  }

  final String pathOrUrl;
  final Widget Function(BuildContext context, String url) builder;
  final Widget? loading;
  final Widget? error;
  final StorageMediaResolver? resolver;

  @override
  State<StorageResolvedImage> createState() => _StorageResolvedImageState();
}

class _StorageResolvedImageState extends State<StorageResolvedImage> {
  late Future<String?> _url;

  StorageMediaResolver get _resolver =>
      widget.resolver ?? StorageMediaResolver.instance;

  @override
  void initState() {
    super.initState();
    _url = _resolver.resolve(widget.pathOrUrl);
  }

  @override
  void didUpdateWidget(covariant StorageResolvedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pathOrUrl != widget.pathOrUrl) {
      _url = _resolver.resolve(widget.pathOrUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cached = StorageMediaRef.isStoragePath(widget.pathOrUrl)
        ? _resolver.cachedUrl(widget.pathOrUrl)
        : null;
    if (cached != null) return widget.builder(context, cached);
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.loading ??
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
        }
        final url = snap.data;
        if (snap.hasError || url == null || url.isEmpty) {
          return widget.error ??
              const Center(child: Icon(Icons.broken_image_rounded));
        }
        return widget.builder(context, url);
      },
    );
  }
}
