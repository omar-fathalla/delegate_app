import 'dart:io';
import 'dart:typed_data';

import 'package:delegate_app/features/tasks/data/services/task_image_storage.dart';
import 'package:delegate_app/features/tasks/domain/task_image_paths.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Rounded thumbnail of a task image. Tapping opens [TaskImageViewer].
///
/// Bytes are loaded through [TaskImageFetcher] (getTaskImage). A stored
/// public download URL is never fetched.
class TaskImageThumbnail extends StatefulWidget {
  const TaskImageThumbnail({
    super.key,
    required this.imagePath,
    this.taskId,
    this.organizationId,
    this.height = 200,
    this.fetcher,
  });

  final String imagePath;
  final String? taskId;
  final String? organizationId;
  final double height;
  final TaskImageFetcher? fetcher;

  @override
  State<TaskImageThumbnail> createState() => _TaskImageThumbnailState();
}

class _TaskImageThumbnailState extends State<TaskImageThumbnail> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(covariant TaskImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath ||
        oldWidget.taskId != widget.taskId ||
        oldWidget.organizationId != widget.organizationId) {
      _bytes = _load();
    }
  }

  Future<Uint8List> _load({bool retrying = false}) async {
    final fetcher =
        widget.fetcher ?? TaskImageFetcher.debugOverride ?? TaskImageFetcher();
    try {
      return await fetcher.load(
        imagePath: widget.imagePath,
        taskId: widget.taskId,
        organizationId: widget.organizationId,
      );
    } catch (e) {
      if (!retrying &&
          widget.taskId != null &&
          !TaskImageFetcher.isAccessDenied(e)) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return _load(retrying: true);
      }
      rethrow;
    }
  }

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
          child: FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snap) {
              if (snap.hasData) {
                final bytes = snap.data!;
                return InkWell(
                  onTap: () => TaskImageViewer.open(context, bytes),
                  child: Hero(
                    tag: 'task-image-${widget.imagePath}',
                    child: Image.memory(
                      bytes,
                      height: widget.height,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              }
              if (snap.hasError) {
                // Viewer can see the task but is not in the send-time grant:
                // hide quietly instead of a broken-load error.
                if (TaskImageFetcher.isAccessDenied(snap.error!)) {
                  return const SizedBox.shrink();
                }
                return SizedBox(
                  height: widget.height,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.broken_image_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.taskImageLoadFailed,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return SizedBox(
                height: widget.height,
                child: const Center(child: CircularProgressIndicator()),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Full-screen, pinch-to-zoom viewer for a task image.
class TaskImageViewer extends StatelessWidget {
  const TaskImageViewer({super.key, required this.bytes});

  final Uint8List bytes;

  static Future<void> open(BuildContext context, Uint8List bytes) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TaskImageViewer(bytes: bytes),
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
          child: Image.memory(bytes, fit: BoxFit.contain),
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
    required this.companyId,
    required this.onChanged,
    this.onUploadingChanged,
    this.initialPath,
    this.initialTaskId,
    this.deleteStorageImmediately = true,
    this.attachLabel,
    this.storage,
    this.picker,
    this.fetcher,
  });

  final String organizationId;
  final String companyId;
  final String? initialPath;
  final String? initialTaskId;

  /// When false (edit screen), picking a replacement or tapping Remove
  /// must not delete the saved object until the sender saves.
  final bool deleteStorageImmediately;

  /// Overrides the empty-state attach button label.
  final String? attachLabel;
  final ValueChanged<TaskImageUpload?> onChanged;
  final ValueChanged<bool>? onUploadingChanged;
  final TaskImageStorage? storage;
  final ImagePicker? picker;
  final TaskImageFetcher? fetcher;

  /// Whether picking a replacement or tapping Remove should delete
  /// [previousPath] immediately. Edit screens pass false and wait for Save.
  @visibleForTesting
  static bool shouldDeleteStoredImageNow({
    required bool deleteStorageImmediately,
    required String? previousPath,
    String? nextPath,
  }) {
    if (!deleteStorageImmediately || previousPath == null) return false;
    if (nextPath != null && nextPath == previousPath) return false;
    return true;
  }

  /// Test/preview seams used when the screen builds the field itself.
  @visibleForTesting
  static TaskImageStorage? debugStorageOverride;
  @visibleForTesting
  static ImagePicker? debugPickerOverride;

  @override
  State<TaskImagePickerField> createState() => _TaskImagePickerFieldState();
}

class _TaskImagePickerFieldState extends State<TaskImagePickerField> {
  String? _path;
  File? _localFile;
  double? _progress;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
  }

  bool get _uploading => _progress != null;

  TaskImageStorage get _storage =>
      widget.storage ??
      TaskImagePickerField.debugStorageOverride ??
      TaskImageStorage();

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
    // image_picker resizes and re-encodes as JPEG: this is the compression
    // and it drops GPS / device metadata from the original file.
    final picked =
        await (widget.picker ??
                TaskImagePickerField.debugPickerOverride ??
                ImagePicker())
            .pickImage(
              source: source,
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 75,
            );
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    if (await file.length() > TaskImageStorage.maxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.taskImageTooLarge)));
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
      final previous = _path;
      final result = await _storage.upload(
        companyId: widget.companyId,
        file: file,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (TaskImagePickerField.shouldDeleteStoredImageNow(
        deleteStorageImmediately: widget.deleteStorageImmediately,
        previousPath: previous,
        nextPath: result.path,
      )) {
        await _storage.deleteQuietly(previous!);
      }
      if (!mounted) return;
      setState(() {
        _path = result.path;
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

  Future<void> _remove() async {
    final previous = _path;
    setState(() {
      _path = null;
      _localFile = null;
      _failed = false;
    });
    widget.onChanged(null);
    if (TaskImagePickerField.shouldDeleteStoredImageNow(
      deleteStorageImmediately: widget.deleteStorageImmediately,
      previousPath: previous,
    )) {
      await _storage.deleteQuietly(previous!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_path == null && _localFile == null) {
      return OutlinedButton.icon(
        onPressed: _chooseSource,
        icon: const Icon(Symbols.add_photo_alternate_rounded),
        label: Text(widget.attachLabel ?? l10n.taskImageAttach),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }

    final Widget preview;
    if (_localFile != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          _localFile!,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else {
      preview = TaskImageThumbnail(
        imagePath: _path!,
        taskId: widget.initialTaskId,
        organizationId: widget.organizationId,
        fetcher: widget.fetcher,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        preview,
        const SizedBox(height: 8),
        if (_uploading) ...[
          Text(
            l10n.taskImageUploading,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
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
                child: Text(
                  l10n.taskImageUploadFailed,
                  style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
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
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant);
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
  const TaskCardMeta({
    super.key,
    required this.hasImage,
    required this.isEdited,
  });

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
            Icon(
              Symbols.image_rounded,
              size: 16,
              color: scheme.primary,
              semanticLabel: l10n.taskImageAttached,
            ),
          if (hasImage && isEdited) const SizedBox(width: 8),
          if (isEdited) const TaskEditedLabel(),
        ],
      ),
    );
  }
}

/// Shows every attached image. Tapping one opens the pinch-zoom viewer.
class TaskImageGallery extends StatelessWidget {
  const TaskImageGallery({
    super.key,
    required this.imagePaths,
    this.taskId,
    this.organizationId,
    this.height = 200,
    this.fetcher,
  });

  final List<String> imagePaths;
  final String? taskId;
  final String? organizationId;
  final double height;
  final TaskImageFetcher? fetcher;

  @override
  Widget build(BuildContext context) {
    final paths = imagePaths
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < paths.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          TaskImageThumbnail(
            key: ValueKey('${paths[i]}#$i'),
            imagePath: paths[i],
            taskId: taskId,
            organizationId: organizationId,
            height: height,
            fetcher: fetcher,
          ),
        ],
      ],
    );
  }
}

/// Lets the sender attach, replace or remove up to [kMaxTaskImages] images.
class TaskImagePickerList extends StatefulWidget {
  const TaskImagePickerList({
    super.key,
    required this.organizationId,
    required this.companyId,
    required this.onChanged,
    this.onUploadingChanged,
    this.initialPaths = const [],
    this.initialTaskId,
    this.deleteStorageImmediately = true,
    this.storage,
    this.picker,
    this.attachLabel,
    this.attachAnotherLabel,
    this.fetcher,
  });

  final String organizationId;
  final String companyId;
  final List<String> initialPaths;
  final String? initialTaskId;
  final bool deleteStorageImmediately;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<bool>? onUploadingChanged;
  final TaskImageStorage? storage;
  final ImagePicker? picker;
  final String? attachLabel;
  final String? attachAnotherLabel;
  final TaskImageFetcher? fetcher;

  @override
  State<TaskImagePickerList> createState() => _TaskImagePickerListState();
}

class _TaskImagePickerListState extends State<TaskImagePickerList> {
  late List<String> _paths;
  final _uploading = <int>{};

  @override
  void initState() {
    super.initState();
    _paths = resolveTaskImagePaths(imagePaths: widget.initialPaths);
  }

  void _emit() => widget.onChanged(List<String>.from(_paths));

  void _setUploading(int index, bool value) {
    if (value) {
      _uploading.add(index);
    } else {
      _uploading.remove(index);
    }
    widget.onUploadingChanged?.call(_uploading.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canAdd = _paths.length < kMaxTaskImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _paths.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          TaskImagePickerField(
            key: ValueKey('slot-$i-${_paths[i]}'),
            organizationId: widget.organizationId,
            companyId: widget.companyId,
            initialPath: _paths[i],
            initialTaskId: widget.initialTaskId,
            deleteStorageImmediately: widget.deleteStorageImmediately,
            storage: widget.storage,
            picker: widget.picker,
            fetcher: widget.fetcher,
            onChanged: (upload) {
              setState(() {
                if (upload == null) {
                  _paths = [..._paths]..removeAt(i);
                } else if (upload.path != _paths[i]) {
                  _paths = [..._paths]..[i] = upload.path;
                }
              });
              _emit();
            },
            onUploadingChanged: (v) => _setUploading(i, v),
          ),
        ],
        if (canAdd) ...[
          if (_paths.isNotEmpty) const SizedBox(height: 12),
          TaskImagePickerField(
            key: ValueKey('slot-new-${_paths.length}'),
            organizationId: widget.organizationId,
            companyId: widget.companyId,
            attachLabel: _paths.isEmpty
                ? widget.attachLabel
                : (widget.attachAnotherLabel ?? l10n.taskImageAttachAnother),
            deleteStorageImmediately: widget.deleteStorageImmediately,
            storage: widget.storage,
            picker: widget.picker,
            fetcher: widget.fetcher,
            onChanged: (upload) {
              if (upload == null) return;
              if (_paths.length >= kMaxTaskImages) return;
              setState(() => _paths = [..._paths, upload.path]);
              _emit();
            },
            onUploadingChanged: (v) => _setUploading(-1, v),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            l10n.taskImageMaxReached,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
