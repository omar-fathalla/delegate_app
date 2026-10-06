import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/core/services/photo_cache_manager.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';
import '../../domain/entities/captured_photo.dart';
import 'package:delegate_app/injection_container.dart' as di;

class CapturedPhotosViewScreen extends StatelessWidget {
  final PhotoPermission photoPermission;

  const CapturedPhotosViewScreen({super.key, required this.photoPermission});

  @override
  Widget build(BuildContext context) {
    PhotoPermissionBloc? existingBloc;
    try {
      existingBloc = context.read<PhotoPermissionBloc>();
    } catch (_) {
      existingBloc = null;
    }

    if (existingBloc != null) {
      return _CapturedPhotosViewContent(photoPermission: photoPermission);
    }

    return BlocProvider<PhotoPermissionBloc>(
      create: (_) => di.sl<PhotoPermissionBloc>(),
      child: _CapturedPhotosViewContent(photoPermission: photoPermission),
    );
  }
}

class _CapturedPhotosViewContent extends StatefulWidget {
  final PhotoPermission photoPermission;

  const _CapturedPhotosViewContent({required this.photoPermission});

  @override
  State<_CapturedPhotosViewContent> createState() => _CapturedPhotosViewContentState();
}

class _CapturedPhotosViewContentState extends State<_CapturedPhotosViewContent> {
  String? _selectedBranchId;
  String? _selectedDelegateUID;
  int _visibleCount = 24;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPhotos();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (mounted) {
        setState(() {
          _visibleCount += 24;
        });
      }
    }
  }

  void _loadPhotos() {
    context.read<PhotoPermissionBloc>().add(
          LoadCapturedPhotosRequested(
            organizationUID: widget.photoPermission.organizationUID,
            companyUID: widget.photoPermission.companyUID,
            permissionId: widget.photoPermission.uid,
          ),
        );
  }

  Future<void> _confirmDeletePhoto(CapturedPhoto photo) async {
    final bloc = context.read<PhotoPermissionBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تأكيد حذف الصورة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من حذف هذه الصورة المرسلة من المندوب "${photo.delegateName}" بفرع "${photo.branchName}"؟',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'سيتم حذف الصورة بشكل نهائي من قاعدة البيانات ومساحة التخزين.',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      bloc.add(
        DeleteCapturedPhotoRequested(
          photoId: photo.uid,
          organizationUID: photo.organizationUID.isNotEmpty
              ? photo.organizationUID
              : widget.photoPermission.organizationUID,
          companyUID: photo.companyUID.isNotEmpty
              ? photo.companyUID
              : widget.photoPermission.companyUID,
          permissionId: photo.permissionId.isNotEmpty
              ? photo.permissionId
              : widget.photoPermission.uid,
          photoUrl: photo.photoUrl,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final permission = widget.photoPermission;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'التقارير المصورة: ${permission.companyName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'من: ${DateFormat('MM-dd').format(permission.startDate)} إلى ${DateFormat('MM-dd').format(permission.endDate)}',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadPhotos,
          ),
        ],
      ),
      body: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        listener: (context, state) {
          if (state is PhotoPermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _loadPhotos();
          } else if (state is PhotoPermissionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is PhotoPermissionLoading) {
            return const Center(
              child: AppLoadingIndicator(
                style: AppLoadingStyle.threeArchedCircle,
                label: 'جاري تحميل التقارير المصورة...',
              ),
            );
          }

          if (state is CapturedPhotosLoaded) {
            final photos = state.photos;
            if (photos.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_search_rounded,
                      size: 72,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لا توجد صور مرفوعة حتى الآن',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            // Extract dynamic options
            final availableBranches = <String, String>{};
            final availableDelegates = <String, String>{};
            for (var photo in photos) {
              if (photo.branchId.isNotEmpty && photo.branchName.isNotEmpty) {
                availableBranches[photo.branchId] = photo.branchName;
              }
              if (photo.delegateUID.isNotEmpty && photo.delegateName.isNotEmpty) {
                availableDelegates[photo.delegateUID] = photo.delegateName;
              }
            }

            // Filter photos
            final filteredPhotos = photos.where((photo) {
              if (_selectedBranchId != null && photo.branchId != _selectedBranchId) {
                return false;
              }
              if (_selectedDelegateUID != null && photo.delegateUID != _selectedDelegateUID) {
                return false;
              }
              return true;
            }).toList();

            return Column(
              children: [
                // Filter Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              isExpanded: true,
                              initialValue: _selectedBranchId,
                              decoration: InputDecoration(
                                labelText: 'تصفية حسب الفرع',
                                prefixIcon: const Icon(Icons.store_rounded, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('جميع الفروع', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                                ...availableBranches.entries.map((e) => DropdownMenuItem<String?>(
                                      value: e.key,
                                      child: Text(e.value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                    )),
                              ],
                              onChanged: (val) => setState(() {
                                _selectedBranchId = val;
                                _visibleCount = 24;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              isExpanded: true,
                              initialValue: _selectedDelegateUID,
                              decoration: InputDecoration(
                                labelText: 'تصفية حسب المندوب',
                                prefixIcon: const Icon(Icons.badge_rounded, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('جميع المناديب', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                                ...availableDelegates.entries.map((e) => DropdownMenuItem<String?>(
                                      value: e.key,
                                      child: Text(e.value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                    )),
                              ],
                              onChanged: (val) => setState(() {
                                _selectedDelegateUID = val;
                                _visibleCount = 24;
                              }),
                            ),
                          ),
                        ],
                      ),
                      if (_selectedBranchId != null || _selectedDelegateUID != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'النتائج المعروضة: ${filteredPhotos.length} من أصل ${photos.length}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedBranchId = null;
                                  _selectedDelegateUID = null;
                                  _visibleCount = 24;
                                });
                              },
                              child: Text(
                                'إلغاء الفلاتر',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Grid Content with pagination
                Expanded(
                  child: filteredPhotos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.filter_list_off_rounded, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                              const SizedBox(height: 16),
                              Text('لا توجد نتائج مطابقة للبحث', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        )
                      : GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: filteredPhotos.take(_visibleCount).length,
                          itemBuilder: (context, index) {
                            final photo = filteredPhotos[index];
                            return GestureDetector(
                              onTap: () => _showFullImage(context, photo),
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                elevation: 3,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          AppPhotoImage(
                                            photoUrl: photo.photoUrl,
                                            isThumbnail: true,
                                            fit: BoxFit.cover,
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                                                ),
                                              ),
                                              padding: const EdgeInsets.all(8),
                                              child: Text(
                                                photo.branchName,
                                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          // زر حذف الصورة السريع
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: Material(
                                              color: Colors.black.withValues(alpha: 0.6),
                                              shape: const CircleBorder(),
                                              child: InkWell(
                                                customBorder: const CircleBorder(),
                                                onTap: () => _confirmDeletePhoto(photo),
                                                child: const Padding(
                                                  padding: EdgeInsets.all(6),
                                                  child: Icon(
                                                    Icons.delete_outline_rounded,
                                                    color: Colors.redAccent,
                                                    size: 18,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.person_rounded, size: 12, color: colorScheme.primary),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  photo.delegateName,
                                                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            photo.comment.isEmpty ? 'بدون تعليق' : photo.comment,
                                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat('MM-dd HH:mm').format(photo.capturedAt),
                                            style: theme.textTheme.labelSmall?.copyWith(fontSize: 9, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (filteredPhotos.length > _visibleCount)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                    ),
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _visibleCount += 24;
                        });
                      },
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(
                        'عرض المزيد (${filteredPhotos.length - _visibleCount} صورة إضافية)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            );
          }

          return const Center(child: Text('جاري جلب الصور والتقارير الميدانية...'));
        },
      ),
    );
  }

  void _showFullImage(BuildContext context, CapturedPhoto photo) {
    final url = photo.photoUrl;
    final comment = photo.comment;
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        bool saveSuccess = false;
        String? statusText;

        return StatefulBuilder(
          builder: (dialogContentContext, setDialogState) {
            final colorScheme = Theme.of(dialogContentContext).colorScheme;
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.black,
                    ),
                    child: InteractiveViewer(
                      maxScale: 4.0,
                      child: AppPhotoImage(
                        photoUrl: url,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _confirmDeletePhoto(photo);
                        },
                        icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 18),
                        label: Text(
                          'حذف الصورة',
                          style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colorScheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isSaving = true;
                                    statusText = null;
                                  });
                                  try {
                                    final success = await PhotoCacheManager.savePhotoToGallery(
                                      context,
                                      photoUrl: url,
                                    );
                                    if (dialogContext.mounted) {
                                      setDialogState(() {
                                        isSaving = false;
                                        saveSuccess = success;
                                        statusText = success
                                            ? 'تم حفظ الصورة في الهاتف بنجاح'
                                            : 'يرجى منح إذن الوصول للصور من الإعدادات.';
                                      });
                                    }
                                  } catch (e) {
                                    if (dialogContext.mounted) {
                                      setDialogState(() {
                                        isSaving = false;
                                        saveSuccess = false;
                                        statusText = 'تعذر حفظ الصورة: $e';
                                      });
                                    }
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(
                                  saveSuccess ? Icons.check_circle_rounded : Icons.download_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            isSaving
                                ? 'جاري حفظ الصورة...'
                                : saveSuccess
                                    ? 'تم الحفظ في الهاتف'
                                    : 'حفظ الصورة',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: saveSuccess ? colorScheme.primary : null,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (statusText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: saveSuccess ? colorScheme.primaryContainer : colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusText!,
                        style: TextStyle(
                          color: saveSuccess ? colorScheme.onPrimaryContainer : colorScheme.onErrorContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (comment.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        comment,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
