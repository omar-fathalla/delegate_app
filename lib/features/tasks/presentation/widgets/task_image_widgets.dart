import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:delegate_app/features/tasks/data/services/task_image_storage.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Rounded thumbnail of a task image. Tapping opens [TaskImageViewer].
class TaskImageThumbnail extends StatelessWidget {
  const TaskImageThumbnail({super.key, required this.url, this.height = 200});

  final String url;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      image: true,
      button: true,
      label: l10n.taskImageAttached,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: scheme.surfaceContainerHighest,
          child: InkWell(
            onTap: () => TaskImageViewer.open(context, url),
            child: Hero(
              tag: 'task-image-$url',
              child: CachedNetworkImage(
                imageUrl: url,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, _) => SizedBox(
                  height: height,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, _, _) => SizedBox(
                  height: height,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.broken_image_rounded,
                            color: scheme.onSurfaceVariant),
                        const SizedBox(height: 4),
                        Text(l10n.taskImageLoadFailed,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
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

/// Full-screen, pinch-to-zoom viewer for a task image.
class TaskImageViewer extends StatelessWidget {
  const TaskImageViewer({super.key, required this.url});

  final String url;

  static Future<void> open(BuildContext context, String url) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TaskImageViewer(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // A viewer reads best on the dark inverse surface in both modes.
    return Scaffold(
      backgroundColor: scheme.inverseSurface,
      appBar: AppBar(
        backgroundColor: scheme.inverseSurface,
        foregroundColor: scheme.onInverseSurface,
        leading: IconButton(
          tooltip: l10n.taskCloseImage,
          icon: const Icon(Symbols.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Hero(
            tag: 'task-image-$url',
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

/// Lets the sender attach, replace or remove the task image.
///
/// Uploads as soon as an image is picked and reports the finished upload
/// through [onChanged] (null when removed). [onUploadingChanged] lets the
/// form disable its submit button while an upload is running.
class TaskImagePickerField extends StatefulWidget {
  const TaskImagePickerField({
    super.key,
    required this.organizationId,
    required this.onChanged,
    this.onUploadingChanged,
    this.initialUrl,
    this.storage,
    this.picker,
  });

  final String organizationId;
  final String? initialUrl;
  final ValueChanged<TaskImageUpload?> onChanged;
  final ValueChanged<bool>? onUploadingChanged;
  final TaskImageStorage? storage;
  final ImagePicker? picker;

  /// Test/preview seams used when the screen builds the field itself.
  @visibleForTesting
  static TaskImageStorage? debugStorageOverride;
  @visibleForTesting
  static ImagePicker? debugPickerOverride;

  @override
  State<TaskImagePickerField> createState() => _TaskImagePickerFieldState();
}

class _TaskImagePickerFieldState extends State<TaskImagePickerField> {
  String? _url;
  File? _localFile;
  double? _progress;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  bool get _uploading => _progress != null;

  Future<void> _chooseSource() async {
    final l10n = AppLocalizations.of(context)!;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.photo_camera_rounded),
              title: Text(l10n.taskImageFromCamera),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Symbols.photo_library_rounded),
              title: Text(l10n.taskImageFromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    // image_picker resizes and re-encodes as JPEG: this is the compression.
    final picked = await (widget.picker ?? TaskImagePickerField.debugPickerOverride ?? ImagePicker()).pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
    );
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    if (await file.length() > TaskImageStorage.maxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.taskImageTooLarge)));
      return;
    }
    setState(() => _localFile = file);
    await _upload();
  }

  Future<void> _upload() async {
    final file = _localFile;
    if (file == null) return;
    setState(() {
      _failed = false;
      _progress = 0;
    });
    widget.onUploadingChanged?.call(true);
    try {
      final result = await (widget.storage ?? TaskImagePickerField.debugStorageOverride ?? TaskImageStorage()).upload(
        organizationId: widget.organizationId,
        file: file,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _url = result.url;
        _progress = null;
      });
      widget.onChanged(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _progress = null;
      });
    } finally {
      widget.onUploadingChanged?.call(false);
    }
  }

  void _remove() {
    setState(() {
      _url = null;
      _localFile = null;
      _failed = false;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_url == null && _localFile == null) {
      return OutlinedButton.icon(
        onPressed: _chooseSource,
        icon: const Icon(Symbols.add_photo_alternate_rounded),
        label: Text(l10n.taskImageAttach),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }

    final preview = _localFile != null && (_uploading || _failed || _url == null)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(_localFile!,
                height: 200, width: double.infinity, fit: BoxFit.cover),
          )
        : TaskImageThumbnail(url: _url!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        preview,
        const SizedBox(height: 8),
        if (_uploading) ...[
          Text(l10n.taskImageUploading,
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: _progress == 0 ? null : _progress,
            borderRadius: BorderRadius.circular(4),
          ),
        ] else if (_failed) ...[
          Row(
            children: [
              Icon(Symbols.error_rounded, color: scheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.taskImageUploadFailed,
                    style: textTheme.bodyMedium?.copyWith(color: scheme.error)),
              ),
              TextButton(onPressed: _upload, child: Text(l10n.taskImageRetry)),
            ],
          ),
        ],
        if (!_uploading)
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _chooseSource,
                icon: const Icon(Symbols.swap_horiz_rounded),
                label: Text(l10n.taskImageReplace),
              ),
              TextButton.icon(
                onPressed: _remove,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Symbols.delete_rounded),
                label: Text(l10n.taskImageRemove),
              ),
            ],
          ),
      ],
    );
  }
}

/// Small "Edited" marker for tasks the sender changed after sending.
class TaskEditedLabel extends StatelessWidget {
  const TaskEditedLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: scheme.onSurfaceVariant);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Symbols.edit_rounded, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(AppLocalizations.of(context)!.taskEditedLabel, style: style),
      ],
    );
  }
}

/// Compact markers for list cards: an image icon and/or the edited label.
class TaskCardMeta extends StatelessWidget {
  const TaskCardMeta({super.key, required this.hasImage, required this.isEdited});

  final bool hasImage;
  final bool isEdited;

  @override
  Widget build(BuildContext context) {
    if (!hasImage && !isEdited) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage)
            Icon(Symbols.image_rounded,
                size: 16,
                color: scheme.primary,
                semanticLabel: l10n.taskImageAttached),
          if (hasImage && isEdited) const SizedBox(width: 8),
          if (isEdited) const TaskEditedLabel(),
        ],
      ),
    );
  }
}
