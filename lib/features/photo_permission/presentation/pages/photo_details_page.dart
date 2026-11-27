import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:delegate_app/core/design/color_schemes.dart';
import 'package:delegate_app/core/design/layout.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/core/design/widgets/toolbar.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:delegate_app/core/services/photo_cache_manager.dart';
import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/captured_photo.dart';

/// **Photo details** (TAS-387, user review 27 Nov 2026), opened from the
/// photo report grid with a container transform. Built from the playground:
///
/// 1. swipe between the photos of the month (`PageView`, «3 من 9»);
/// 2. tap the photo to hide everything else, double tap to zoom ×2, pinch to
///    zoom; the hint is a tooltip shown once;
/// 3. a photo that fails to load shows `EmptyState` with retry;
/// 4. a floating toolbar (C-07): save, share, open on the map; delete stays
///    in the ⋮ menu (managers only);
/// 5. the details as an official list (C-23), the branch with an assist chip
///    «افتح على الخريطة» (C-11), the comment in its own outlined card;
/// 6. a photo still on the phone shows a `MaterialBanner` (C-34);
/// 7. the time also as relative time;
/// 8. wide windows (F-07): photo and details side by side, arrows for the
///    mouse;
/// 9. the photo is described to screen readers, every button has a tooltip;
/// 10. the details take their colours from the photo (`ContentColorScope`);
/// 11. a small map of where the photo was taken.
class PhotoDetailsPage extends StatefulWidget {
  const PhotoDetailsPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.companyFallback,
    this.onDelete,
  });

  /// The photos to swipe through (the month, in grid order).
  final List<CapturedPhoto> photos;
  final int initialIndex;
  final String companyFallback;

  /// Asks to delete (kit dialog); returns true when the delete was sent.
  final Future<bool> Function(BuildContext context, CapturedPhoto photo)?
  onDelete;

  /// The live map preview (11). Off on the web (no Maps JS key there) and in
  /// widget tests (no platform view).
  static bool mapPreviewEnabled = !kIsWeb;

  /// The zoom hint is shown once per app run.
  static bool _hintShown = false;

  @override
  State<PhotoDetailsPage> createState() => _PhotoDetailsPageState();
}

class _PhotoDetailsPageState extends State<PhotoDetailsPage> {
  late int _index = widget.initialIndex;
  late PageController _pages = PageController(initialPage: _index);
  bool _immersive = false;
  bool _zoomed = false;
  bool _saving = false;
  final Set<String> _bannerClosed = {};

  CapturedPhoto get _photo => widget.photos[_index];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _setImmersive(bool on) {
    final old = _pages;
    setState(() {
      _immersive = on;
      _pages = PageController(initialPage: _index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.photos.length) return;
    _pages.animateToPage(
      next,
      duration: MediaQuery.maybeDisableAnimationsOf(context) == true
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  bool get _hasLocation => _photo.latitude != 0 || _photo.longitude != 0;

  Uri _mapUri(CapturedPhoto p) => Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}',
  );

  Future<void> _openMap() async {
    final ok = await launchUrl(
      _mapUri(_photo),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      showTashilSnackBar(context, AppLocalizations.of(context)!.photoMapFailed);
    }
  }

  Future<File?> _fileFor(CapturedPhoto p) async {
    final url = p.photoUrl;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return PhotoCacheManager.instance.getSingleFile(url);
    }
    return PhotoCacheManager.fileForStoredPhoto(url);
  }

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context)!;
    final p = _photo;
    try {
      final file = await _fileFor(p);
      if (file == null) throw Exception('no file');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/jpeg')],
          text:
              '${BranchDisplayCache.instance.displayName(p.branchName)} • ${_fullTime(p.capturedAt)}',
        ),
      );
    } catch (_) {
      if (mounted) showTashilSnackBar(context, l10n.photoShareFailed);
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    String message;
    try {
      final ok = await PhotoCacheManager.savePhotoToGallery(
        context,
        photoUrl: _photo.photoUrl,
      );
      message = ok ? l10n.photoSavedToGallery : l10n.grantPhotosPermission;
    } catch (e) {
      message = l10n.photoSaveFailed(e);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showTashilSnackBar(context, message);
  }

  Future<void> _delete() async {
    final sent = await widget.onDelete!(context, _photo);
    if (sent && mounted) Navigator.of(context).pop(true);
  }

  String _fullTime(DateTime t) => DateFormat(
    'EEEE، d MMMM • h:mm a',
    Localizations.localeOf(context).languageCode,
  ).format(t);

  /// «منذ ساعتين», «أمس», «منذ 3 أيام» (7).
  String _relative(DateTime t) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final d = now.difference(t);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final days = today.difference(day).inDays;
    if (days == 0) {
      if (d.inMinutes < 60)
        return l10n.timeAgoMinutes(d.inMinutes.clamp(1, 59));
      return l10n.timeAgoHours(d.inHours);
    }
    if (days == 1) return l10n.yesterday;
    return l10n.timeAgoDays(days);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final wide =
        TashilBreakpoint.of(context).index >= TashilBreakpoint.expanded.index;
    // An Arabic phrase, so no Bidi.ltr around it.
    final counter = l10n.photoCounter(_index + 1, widget.photos.length);

    if (_immersive) {
      // Light status bar icons on the scrim.
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          key: const Key('photo_details_immersive'),
          backgroundColor: cs.scrim,
          body: SafeArea(child: _pager(fill: true)),
        ),
      );
    }

    final actions = <ToolbarAction>[
      ToolbarAction(
        icon: _saving ? Symbols.downloading_rounded : Symbols.download_rounded,
        label: l10n.savePhoto,
        onPressed: _saving ? null : _save,
      ),
      if (!kIsWeb)
        ToolbarAction(
          icon: Symbols.share_rounded,
          label: l10n.photoShare,
          onPressed: _share,
        ),
      if (_hasLocation)
        ToolbarAction(
          icon: Symbols.map_rounded,
          label: l10n.photoOpenMap,
          onPressed: _openMap,
        ),
    ];

    final menu = widget.onDelete == null
        ? null
        : MenuAnchor(
            builder: (context, controller, _) => IconButton(
              key: const Key('photo_details_menu'),
              icon: const Icon(Symbols.more_vert_rounded),
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              MenuItemButton(
                key: const Key('photo_details_delete'),
                leadingIcon: const Icon(Symbols.delete_outline_rounded),
                onPressed: _delete,
                child: Text(l10n.deletePhoto),
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.photoDetails),
            if (widget.photos.length > 1)
              Text(
                counter,
                key: const Key('photo_details_counter'),
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
        actions: [?menu],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: TashilToolbar(
        key: const Key('photo_details_toolbar'),
        actions: actions,
      ),
      body: wide
          ? Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(TashilSpacing.page),
                    child: Stack(
                      children: [
                        Positioned.fill(child: _pager(fill: true)),
                        if (widget.photos.length > 1) ...[
                          PositionedDirectional(
                            start: TashilSpacing.sm,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: IconButton.filledTonal(
                                key: const Key('photo_details_previous'),
                                tooltip: l10n.photoPrevious,
                                icon: const Icon(Symbols.chevron_left_rounded),
                                onPressed: _index > 0 ? () => _go(-1) : null,
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            end: TashilSpacing.sm,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: IconButton.filledTonal(
                                key: const Key('photo_details_next'),
                                tooltip: l10n.photoNext,
                                icon: const Icon(Symbols.chevron_right_rounded),
                                onPressed: _index < widget.photos.length - 1
                                    ? () => _go(1)
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 380,
                  child: ListView(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      0,
                      TashilSpacing.page,
                      TashilSpacing.page,
                      TashilSpacing.xxl * 2,
                    ),
                    children: _details(_photo),
                  ),
                ),
              ],
            )
          : _pager(fill: false),
    );
  }

  /// The swipeable photos. [fill]: the photo alone fills the space
  /// (immersive, wide); otherwise each page is the photo and its details.
  Widget _pager({required bool fill}) {
    return PageView.builder(
      key: const Key('photo_details_pager'),
      controller: _pages,
      physics: _zoomed
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      itemCount: widget.photos.length,
      onPageChanged: (i) => setState(() {
        _index = i;
        _zoomed = false;
      }),
      itemBuilder: (context, i) {
        final p = widget.photos[i];
        final photo = _ZoomablePhoto(
          key: ValueKey('zoom_${p.uid}_$fill'),
          photo: p,
          semanticLabel: AppLocalizations.of(context)!.photoSemantic(
            BranchDisplayCache.instance.displayName(p.branchName),
            _fullTime(p.capturedAt),
          ),
          showHint: i == widget.initialIndex && !PhotoDetailsPage._hintShown,
          onHintShown: () => PhotoDetailsPage._hintShown = true,
          onTap: () => _setImmersive(!_immersive),
          onZoomChanged: (z) {
            if (z != _zoomed) setState(() => _zoomed = z);
          },
          fill: fill,
        );
        if (fill) return photo;
        return ListView(
          key: ValueKey('photo_page_${p.uid}'),
          padding: const EdgeInsetsDirectional.fromSTEB(
            TashilSpacing.page,
            TashilSpacing.sm,
            TashilSpacing.page,
            TashilSpacing.xxl * 2,
          ),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(TashilRadius.large),
              child: AspectRatio(aspectRatio: 3 / 4, child: photo),
            ),
            ..._details(p),
          ],
        );
      },
    );
  }

  /// Banner + details (5, 6, 7, 10, 11).
  List<Widget> _details(CapturedPhoto p) {
    final l10n = AppLocalizations.of(context)!;
    final pending = p.uid.startsWith('pending_');
    final hasLocation = p.latitude != 0 || p.longitude != 0;
    return [
      if (pending && !_bannerClosed.contains(p.uid))
        Padding(
          padding: const EdgeInsetsDirectional.only(top: TashilSpacing.md),
          child: MaterialBanner(
            key: const Key('photo_details_pending_banner'),
            leading: const Icon(Symbols.cloud_off_rounded),
            content: Text(l10n.photoPendingBanner),
            actions: [
              TextButton(
                onPressed: () => setState(() => _bannerClosed.add(p.uid)),
                child: Text(l10n.photoBannerOk),
              ),
            ],
          ),
        ),
      _PhotoColours(
        photo: p,
        child: Builder(
          builder: (context) {
            final cs = Theme.of(context).colorScheme;
            final tt = Theme.of(context).textTheme;
            Widget tile(
              IconData icon,
              String label,
              String value, {
              Widget? trailing,
              Key? key,
            }) => ListTile(
              key: key,
              leading: Icon(icon, color: cs.primary),
              title: Text(value, style: tt.bodyLarge),
              subtitle: Text(
                label,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: trailing,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: TashilSpacing.md),
                Card.filled(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      tile(
                        Symbols.storefront_rounded,
                        l10n.branchField,
                        BranchDisplayCache.instance.displayName(p.branchName),
                        trailing: hasLocation
                            ? ActionChip(
                                key: const Key('photo_details_map_chip'),
                                avatar: const Icon(Symbols.map_rounded),
                                label: Text(l10n.photoOpenMap),
                                onPressed: () => launchUrl(
                                  _mapUri(p),
                                  mode: LaunchMode.externalApplication,
                                ),
                              )
                            : null,
                      ),
                      const Divider(height: 1, indent: TashilSpacing.xxl * 2),
                      tile(
                        Symbols.schedule_rounded,
                        '${l10n.capturedAtField} • ${_relative(p.capturedAt)}',
                        _fullTime(p.capturedAt),
                        key: const Key('photo_details_time'),
                      ),
                      const Divider(height: 1, indent: TashilSpacing.xxl * 2),
                      tile(
                        Symbols.person_rounded,
                        l10n.delegateField,
                        p.delegateName,
                      ),
                      const Divider(height: 1, indent: TashilSpacing.xxl * 2),
                      tile(
                        Symbols.business_rounded,
                        l10n.companyLabel,
                        p.companyName.isNotEmpty
                            ? p.companyName
                            : widget.companyFallback,
                      ),
                    ],
                  ),
                ),
                if (p.comment.trim().isNotEmpty) ...[
                  const SizedBox(height: TashilSpacing.md),
                  Card.outlined(
                    key: const Key('photo_details_comment'),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(TashilSpacing.lg),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Symbols.format_quote_rounded, color: cs.primary),
                          const SizedBox(width: TashilSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.delegateCommentField,
                                  style: tt.labelMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: TashilSpacing.xs),
                                Text(p.comment.trim(), style: tt.bodyLarge),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (hasLocation && PhotoDetailsPage.mapPreviewEnabled) ...[
                  const SizedBox(height: TashilSpacing.md),
                  _MapPreview(
                    key: ValueKey('photo_map_${p.uid}'),
                    lat: p.latitude,
                    lng: p.longitude,
                    onTap: () => launchUrl(
                      _mapUri(p),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ];
  }
}

/// The photo with pinch zoom, double tap ×2 and a one-tap callback (2), a
/// screen-reader label (9) and EmptyState + retry when it fails (3).
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.photo,
    required this.semanticLabel,
    required this.showHint,
    required this.onHintShown,
    required this.onTap,
    required this.onZoomChanged,
    required this.fill,
  });

  final CapturedPhoto photo;
  final String semanticLabel;
  final bool showHint;
  final VoidCallback onHintShown;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;
  final bool fill;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _zoom = TransformationController();
  final _hint = GlobalKey<TooltipState>();
  Offset _tapAt = Offset.zero;
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    if (widget.showHint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _hint.currentState?.ensureTooltipVisible();
        widget.onHintShown();
      });
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _report() =>
      widget.onZoomChanged(_zoom.value.getMaxScaleOnAxis() > 1.01);

  void _doubleTap() {
    if (_zoom.value.getMaxScaleOnAxis() > 1.01) {
      _zoom.value = Matrix4.identity();
    } else {
      const s = 2.0;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _report();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      key: _hint,
      message: l10n.pinchToZoom,
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        image: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTapDown: (d) => _tapAt = d.localPosition,
          onDoubleTap: _doubleTap,
          child: ColoredBox(
            color: widget.fill
                ? Colors.transparent
                : cs.surfaceContainerHighest,
            child: InteractiveViewer(
              transformationController: _zoom,
              minScale: 1,
              maxScale: 4,
              onInteractionEnd: (_) => _report(),
              child: Center(
                child: AppPhotoImage(
                  key: ValueKey('photo_${widget.photo.uid}_$_retry'),
                  photoUrl: widget.photo.photoUrl,
                  fit: BoxFit.contain,
                  errorWidget: SingleChildScrollView(
                    child: EmptyState(
                      key: const Key('photo_details_load_failed'),
                      icon: Symbols.broken_image_rounded,
                      title: l10n.photoLoadFailed,
                      action: FilledButton.tonalIcon(
                        onPressed: () => setState(() => _retry++),
                        icon: const Icon(Symbols.refresh_rounded),
                        label: Text(l10n.retry),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Content-based colour (10): the details take their scheme from the photo
/// (kit `ContentColorScope`, Flutter's `ColorScheme.fromImageProvider`). Until
/// the photo is resolved, the app scheme.
class _PhotoColours extends StatefulWidget {
  const _PhotoColours({required this.photo, required this.child});
  final CapturedPhoto photo;
  final Widget child;

  @override
  State<_PhotoColours> createState() => _PhotoColoursState();
}

class _PhotoColoursState extends State<_PhotoColours> {
  ImageProvider? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final stored = widget.photo.photoUrl;
    ImageProvider? image;
    try {
      if (stored.startsWith('http://') || stored.startsWith('https://')) {
        image = CachedNetworkImageProvider(
          stored,
          cacheManager: PhotoCacheManager.instance,
        );
      } else if (StorageMediaRef.isStoragePath(stored)) {
        final url = await StorageMediaResolver.instance.tryResolve(stored);
        if (url != null) {
          image = CachedNetworkImageProvider(
            url,
            cacheKey: stored,
            cacheManager: PhotoCacheManager.instance,
          );
        }
      } else if (!kIsWeb && stored.isNotEmpty) {
        final file = await PhotoCacheManager.resolveLocalPhotoFile(stored);
        if (file != null && file.existsSync()) image = FileImage(file);
      }
    } catch (_) {}
    if (mounted && image != null) setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return widget.child;
    return ContentColorScope(image: image, child: widget.child);
  }
}

/// A small, non-interactive map of where the photo was taken (11). Tapping
/// it opens the map app.
class _MapPreview extends StatelessWidget {
  const _MapPreview({
    super.key,
    required this.lat,
    required this.lng,
    required this.onTap,
  });

  final double lat;
  final double lng;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final at = LatLng(lat, lng);
    return Card.filled(
      key: const Key('photo_details_map'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 160,
        child: Stack(
          children: [
            IgnorePointer(
              child: GoogleMap(
                liteModeEnabled: true,
                initialCameraPosition: CameraPosition(target: at, zoom: 16),
                markers: {
                  Marker(markerId: const MarkerId('photo'), position: at),
                },
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
