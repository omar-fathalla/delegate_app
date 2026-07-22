import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';

class CapturedPhotosViewScreen extends StatefulWidget {
  final PhotoPermission photoPermission;

  const CapturedPhotosViewScreen({super.key, required this.photoPermission});

  @override
  State<CapturedPhotosViewScreen> createState() => _CapturedPhotosViewScreenState();
}

class _CapturedPhotosViewScreenState extends State<CapturedPhotosViewScreen> {
  String? _selectedBranchId;
  String? _selectedDelegateUID;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
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
      body: BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
        builder: (context, state) {
          if (state is PhotoPermissionLoading) {
            return const Center(child: CircularProgressIndicator());
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
                    const SizedBox(height: 8),
                    Text(
                      'سيظهر هنا عمل المناديب فور التقاطهم صور في الفروع.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
              availableBranches[photo.branchId] = photo.branchName;
              availableDelegates[photo.delegateUID] = photo.delegateName;
            }

            // Filter photos
            final filteredPhotos = photos.where((photo) {
              final matchBranch = _selectedBranchId == null || photo.branchId == _selectedBranchId;
              final matchDelegate = _selectedDelegateUID == null || photo.delegateUID == _selectedDelegateUID;
              return matchBranch && matchDelegate;
            }).toList();

            return Column(
              children: [
                // Filter Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      // Branch Filter
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedBranchId,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            labelText: 'تصفية بالفرع',
                            labelStyle: const TextStyle(fontSize: 12),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('كل الفروع', style: TextStyle(fontSize: 12)),
                            ),
                            ...availableBranches.entries.map((e) => DropdownMenuItem<String>(
                                  value: e.key,
                                  child: Text(e.value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedBranchId = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Delegate Filter
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedDelegateUID,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            labelText: 'تصفية بالمندوب',
                            labelStyle: const TextStyle(fontSize: 12),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('كل المناديب', style: TextStyle(fontSize: 12)),
                            ),
                            ...availableDelegates.entries.map((e) => DropdownMenuItem<String>(
                                  value: e.key,
                                  child: Text(e.value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedDelegateUID = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Grid Content
                Expanded(
                  child: filteredPhotos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.filter_list_off_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'لا توجد نتائج مطابقة للبحث',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedBranchId = null;
                                    _selectedDelegateUID = null;
                                  });
                                },
                                icon: const Icon(Icons.clear_all_rounded),
                                label: const Text('إعادة تعيين الفلاتر'),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: filteredPhotos.length,
                          itemBuilder: (context, index) {
                            final photo = filteredPhotos[index];
                            return GestureDetector(
                              onTap: () => _showFullImage(context, photo.photoUrl, photo.comment),
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.network(
                                            photo.photoUrl,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) return child;
                                              return const Center(
                                                child: CircularProgressIndicator(),
                                              );
                                            },
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                color: colorScheme.errorContainer,
                                                child: Icon(
                                                  Icons.broken_image_rounded,
                                                  color: colorScheme.onErrorContainer,
                                                ),
                                              );
                                            },
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
                                                  colors: [
                                                    Colors.black.withValues(alpha: 0.8),
                                                    Colors.transparent,
                                                  ],
                                                ),
                                              ),
                                              padding: const EdgeInsets.all(8),
                                              child: Text(
                                                photo.branchName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            photo.comment.isEmpty ? 'بدون تعليق' : photo.comment,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              fontSize: 11,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat('MM-dd HH:mm').format(photo.capturedAt),
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontSize: 9,
                                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                            ),
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
              ],
            );
          }

          return const Center(child: Text('جاري جلب الصور والتقارير الميدانية...'));
        },
      ),
    );
  }

  void _showFullImage(BuildContext context, String url, String comment) {
    showDialog(
      context: context,
      builder: (context) {
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
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 12),
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
  }
}
