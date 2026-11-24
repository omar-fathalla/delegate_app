import 'dart:io';

import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// What the user chose in [CapturedPhotoFullScreenViewer].
enum CapturedPhotoViewerAction { retake, delete }

/// TAS-302: shows one captured (stamped) photo on the whole screen, uncropped,
/// so the delegate can check the branch and date strip before sending.
///
/// Pops with [CapturedPhotoViewerAction.retake] or
/// [CapturedPhotoViewerAction.delete], or `null` when closed.
class CapturedPhotoFullScreenViewer extends StatelessWidget {
  final File photo;
  final int photoNumber;

  const CapturedPhotoFullScreenViewer({
    super.key,
    required this.photo,
    required this.photoNumber,
  });

  static Future<CapturedPhotoViewerAction?> open(
    BuildContext context, {
    required File photo,
    required int photoNumber,
  }) {
    return Navigator.of(context).push<CapturedPhotoViewerAction>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CapturedPhotoFullScreenViewer(
          photo: photo,
          photoNumber: photoNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          l10n.photoNumber(photoNumber),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          key: const ValueKey('captured_photo_viewer_close'),
          icon: const Icon(Icons.close_rounded),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: Image.file(
                    photo,
                    key: const ValueKey('captured_photo_viewer_image'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey('captured_photo_viewer_retake'),
                    onPressed: () => Navigator.of(context).pop(CapturedPhotoViewerAction.retake),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l10n.retakePhoto),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const Spacer(),
                  IconButton.filled(
                    key: const ValueKey('captured_photo_viewer_delete'),
                    onPressed: () => Navigator.of(context).pop(CapturedPhotoViewerAction.delete),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    tooltip: l10n.deletePhoto,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.85),
                      foregroundColor: Colors.white,
                    ),
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
