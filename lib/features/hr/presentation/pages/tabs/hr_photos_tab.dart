import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:delegate_app/core/services/photo_cache_manager.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission_departments.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/captured_photos_view_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;

class HRPhotosTab extends StatefulWidget {
  final Delegate hrDelegate;

  const HRPhotosTab({super.key, required this.hrDelegate});

  @override
  State<HRPhotosTab> createState() => _HRPhotosTabState();
}

class _HRPhotosTabState extends State<HRPhotosTab> {
  int _selectedView = 0; // 0 = الصور الميدانية, 1 = أذونات التصوير
  final TextEditingController _searchController = TextEditingController();

  // Filters for View 0 (الصور الميدانية)
  String _selectedBranch = 'all';
  String _selectedDelegate = 'all';

  // Filters for View 1 (أذونات التصوير)
  String _selectedPermissionFilter = 'all'; // all, active, pending, expired

  late PhotoPermissionBloc _photoBloc;

  @override
  void initState() {
    super.initState();
    _photoBloc = di.sl<PhotoPermissionBloc>();
    _refreshData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _photoBloc.close();
    super.dispose();
  }

  void _refreshData() {
    if (_selectedView == 0) {
      _photoBloc.add(
        LoadCompanyCapturedPhotosRequested(
          companyUID: widget.hrDelegate.companyUID,
        ),
      );
    } else {
      _photoBloc.add(
        LoadPermissionsRequested(
          organizationUID: widget.hrDelegate.organizationUID,
          companyUID: widget.hrDelegate.companyUID,
        ),
      );
    }
  }

  void _showCreateRequestSheet(BuildContext context) {
    final state = _photoBloc.state;
    if (state is PhotoPermissionsLoaded) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final hasActiveOrPending = state.permissions.any((p) {
        final isPending = p.status.toLowerCase() == 'pending';
        final isActive = p.status.toLowerCase() == 'approved' && !p.endDate.isBefore(todayStart);
        return isPending || isActive;
      });

      if (hasActiveOrPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ يوجد بالفعل إذن تصوير فعال أو معلق قيد المراجعة لهذه الشركة. لا يمكن تقديم طلب جديد حتى انتهاء الإذن الحالي.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => di.sl<BranchBloc>()..add(BranchLoadRequested())),
            BlocProvider.value(value: _photoBloc),
          ],
          child: _HRCreatePhotoRequestBottomSheet(
            hrDelegate: widget.hrDelegate,
            photoBloc: _photoBloc,
          ),
        );
      },
    );
  }

  Future<void> _confirmDeletePhoto(CapturedPhoto photo) async {
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
      _photoBloc.add(
        DeleteCapturedPhotoRequested(
          photoId: photo.uid,
          organizationUID: photo.organizationUID.isNotEmpty
              ? photo.organizationUID
              : widget.hrDelegate.organizationUID,
          companyUID: photo.companyUID.isNotEmpty
              ? photo.companyUID
              : widget.hrDelegate.companyUID,
          permissionId: photo.permissionId,
          photoUrl: photo.photoUrl,
        ),
      );
    }
  }

  Future<void> _confirmCancelPermission(PhotoPermission permission) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('إلغاء طلب إذن التصوير'),
        content: const Text('هل أنت متأكد من رغبتك في إلغاء هذا الطلب المعلق؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _photoBloc.add(
        DeletePhotoPermissionRequested(
          organizationUID: permission.organizationUID,
          companyUID: permission.companyUID,
          permissionId: permission.uid,
        ),
      );
    }
  }

  void _openPhotoDetail(CapturedPhoto photo) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        bool isSaving = false;
        bool saveSuccess = false;
        String? statusText;

        return StatefulBuilder(
          builder: (dialogContentContext, setDialogState) {
            final colorScheme = Theme.of(dialogContentContext).colorScheme;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Action Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        photo.delegateName.isNotEmpty
                            ? photo.delegateName
                            : 'معاينة الصورة الميدانية',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Interactive Image Viewer
                  Flexible(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: AppPhotoImage(
                          photoUrl: photo.photoUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Metadata Info Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.storefront_rounded, size: 16, color: Colors.amber),
                            const SizedBox(width: 6),
                            Text(
                              photo.branchName.isNotEmpty ? photo.branchName : 'الفرع غير محدد',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.schedule_rounded, size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(photo.capturedAt),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        if (photo.comment.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'ملاحظات: ${photo.comment}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Action Buttons (Delete & Save to Phone)
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
                                      photoUrl: photo.photoUrl,
                                    );
                                    if (dialogContentContext.mounted) {
                                      setDialogState(() {
                                        isSaving = false;
                                        saveSuccess = success;
                                        statusText = success
                                            ? 'تم حفظ الصورة في الهاتف بنجاح'
                                            : 'يرجى منح إذن الوصول للصور من الإعدادات.';
                                      });
                                    }
                                  } catch (e) {
                                    if (dialogContentContext.mounted) {
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
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocProvider.value(
      value: _photoBloc,
      child: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        listener: (context, state) {
          if (state is PermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _refreshData();
          } else if (state is PhotoPermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _refreshData();
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
          return Column(
            children: [
              // ── Top Header with M3 Connected Button Group & Actions ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 680;

                    final buttonGroup = TashilConnectedButtonGroup<int>(
                      isScrollable: true,
                      height: 44,
                      selectedValue: _selectedView,
                      items: const [
                        TashilConnectedButtonItem(
                          value: 0,
                          label: 'الصور الميدانية',
                          icon: Icons.photo_library_rounded,
                        ),
                        TashilConnectedButtonItem(
                          value: 1,
                          label: 'أذونات التصوير',
                          icon: Icons.verified_rounded,
                        ),
                      ],
                      onSelected: (val) {
                        setState(() {
                          _selectedView = val;
                          _selectedBranch = 'all';
                          _selectedDelegate = 'all';
                          _selectedPermissionFilter = 'all';
                          _searchController.clear();
                        });
                        _refreshData();
                      },
                    );

                    final actionButtons = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildM3ActionButtonsGroup(colorScheme),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            minimumSize: const Size(44, 44),
                          ),
                          tooltip: 'تحديث البيانات',
                          onPressed: _refreshData,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                        ),
                      ],
                    );

                    if (isNarrow) {
                      return Column(
                        children: [
                          Center(child: buttonGroup),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: actionButtons,
                          ),
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        buttonGroup,
                        actionButtons,
                      ],
                    );
                  },
                ),
              ),

              // ── Content View ──
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (state is PhotoPermissionLoading) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (state is PhotoPermissionError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                            const SizedBox(height: 12),
                            Text(state.message, style: TextStyle(color: colorScheme.error)),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: _refreshData,
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      );
                    } else if (_selectedView == 0 && state is CapturedPhotosLoaded) {
                      return _buildCapturedPhotosGrid(state.photos, theme, colorScheme);
                    } else if (_selectedView == 1 && state is PhotoPermissionsLoaded) {
                      return _buildPermissionsList(state.permissions, theme, colorScheme);
                    }

                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // TAB 0: الصور الميدانية مع فلترة الفروع والمناديب والمكتبة
  // ─────────────────────────────────────────────────────────
  Widget _buildCapturedPhotosGrid(
    List<CapturedPhoto> photos,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // Extract unique branch and delegate names and calculate counts
    final uniqueBranches = <String>{};
    final uniqueDelegates = <String>{};
    final branchCounts = <String, int>{};
    final delegateCounts = <String, int>{};

    for (final p in photos) {
      if (p.branchName.trim().isNotEmpty) {
        final b = p.branchName.trim();
        uniqueBranches.add(b);
        branchCounts[b] = (branchCounts[b] ?? 0) + 1;
      }
      if (p.delegateName.trim().isNotEmpty) {
        final d = p.delegateName.trim();
        uniqueDelegates.add(d);
        delegateCounts[d] = (delegateCounts[d] ?? 0) + 1;
      }
    }
    final sortedBranches = uniqueBranches.toList()..sort();
    final sortedDelegates = uniqueDelegates.toList()..sort();

    final query = _searchController.text.trim().toLowerCase();
    final filtered = photos.where((p) {
      if (query.isNotEmpty) {
        final matchesName = p.delegateName.toLowerCase().contains(query);
        final matchesBranch = p.branchName.toLowerCase().contains(query);
        final matchesComment = p.comment.toLowerCase().contains(query);
        if (!matchesName && !matchesBranch && !matchesComment) return false;
      }
      if (_selectedBranch != 'all' && p.branchName != _selectedBranch) {
        return false;
      }
      if (_selectedDelegate != 'all' && p.delegateName != _selectedDelegate) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Filter Controls Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 1.0,
              ),
            ),
          ),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 768;

                  if (isDesktop) {
                    return Row(
                      children: [
                        // Search Bar (flex 4)
                        Expanded(
                          flex: 4,
                          child: _buildPhotosSearchBar(colorScheme),
                        ),
                        const SizedBox(width: 10),
                        // Branch Dropdown (flex 3)
                        Expanded(
                          flex: 3,
                          child: _buildM3BranchDropdown(
                            sortedBranches: sortedBranches,
                            branchCounts: branchCounts,
                            colorScheme: colorScheme,
                            totalPhotos: photos.length,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Delegate Dropdown (flex 3)
                        Expanded(
                          flex: 3,
                          child: _buildM3DelegateDropdown(
                            sortedDelegates: sortedDelegates,
                            delegateCounts: delegateCounts,
                            colorScheme: colorScheme,
                            totalPhotos: photos.length,
                          ),
                        ),
                      ],
                    );
                  }

                  // Narrow / Mobile screen layout
                  return Column(
                    children: [
                      _buildPhotosSearchBar(colorScheme),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildM3BranchDropdown(
                              sortedBranches: sortedBranches,
                              branchCounts: branchCounts,
                              colorScheme: colorScheme,
                              totalPhotos: photos.length,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildM3DelegateDropdown(
                              sortedDelegates: sortedDelegates,
                              delegateCounts: delegateCounts,
                              colorScheme: colorScheme,
                              totalPhotos: photos.length,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              // Summary & Clear Filters Bar
              if (_selectedBranch != 'all' || _selectedDelegate != 'all' || _searchController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'النتائج المعروضة: ${filtered.length} من أصل ${photos.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedBranch = 'all';
                          _selectedDelegate = 'all';
                          _searchController.clear();
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

        // Grid Content
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 56,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        photos.isEmpty
                            ? 'لا توجد صور معاينة ميدانية مسجلة حتى الآن'
                            : 'لا توجد صور معاينة ميدانية مطابقة للبحث أو الفلتر',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_selectedBranch != 'all' || _selectedDelegate != 'all' || _searchController.text.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () {
                            setState(() {
                              _selectedBranch = 'all';
                              _selectedDelegate = 'all';
                              _searchController.clear();
                            });
                          },
                          child: const Text('إلغاء الفلاتر وإظهار الكل'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => _refreshData(),
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final photo = filtered[index];
                      return InkWell(
                        onTap: () => _openPhotoDetail(photo),
                        borderRadius: BorderRadius.circular(16),
                        child: Card(
                          elevation: 0,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AppPhotoImage(
                                photoUrl: photo.photoUrl,
                                isThumbnail: true,
                                fit: BoxFit.cover,
                              ),
                              // Gradient Overlay
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.25),
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.8),
                                      ],
                                      stops: const [0.0, 0.4, 1.0],
                                    ),
                                  ),
                                ),
                              ),

                              // Bottom Info
                              Positioned(
                                bottom: 8,
                                left: 8,
                                right: 8,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      photo.delegateName.isNotEmpty ? photo.delegateName : 'مندوب',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.storefront_rounded, size: 12, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            photo.branchName,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('MM/dd - hh:mm a', 'ar').format(photo.capturedAt),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
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
        ),
      ],
    );
  }

  // ── M3 Connected Action Button Group (طلب إذن تصوير + التقرير الشهري) ──
  Widget _buildM3ActionButtonsGroup(ColorScheme colorScheme) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // طلب إذن تصوير (Primary Action)
          Material(
            color: colorScheme.primary,
            child: InkWell(
              onTap: () => _showCreateRequestSheet(context),
              hoverColor: colorScheme.onPrimary.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_a_photo_rounded,
                      size: 18,
                      color: colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'طلب إذن تصوير',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Subtle vertical divider between the two buttons
          Container(
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          // التقرير الشهري (Secondary Tonal Action)
          Material(
            color: colorScheme.surfaceContainerHigh,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlocProvider(
                      create: (_) => di.sl<PhotoPermissionBloc>(),
                      child: MonthlyPhotoReportScreen(
                        delegate: widget.hrDelegate,
                        showAppBar: true,
                      ),
                    ),
                  ),
                );
              },
              hoverColor: colorScheme.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'التقرير الشهري',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── M3 Web Search Bar (Height 44dp) ──
  Widget _buildPhotosSearchBar(
    ColorScheme colorScheme, {
    String hintText = 'بحث باسم المندوب أو الفرع أو ملاحظات...',
  }) {
    final hasText = _searchController.text.isNotEmpty;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasText
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: hasText ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 19,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (hasText)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                _searchController.clear();
                setState(() {});
              },
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(
                  Icons.clear_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── M3 Branch Filter Dropdown (Height 44dp, LayoutBuilder matching width) ──
  Widget _buildM3BranchDropdown({
    required List<String> sortedBranches,
    required Map<String, int> branchCounts,
    required ColorScheme colorScheme,
    required int totalPhotos,
  }) {
    final isFiltered = _selectedBranch != 'all';
    final currentLabel = isFiltered ? _selectedBranch : 'جميع الفروع';

    return LayoutBuilder(
      builder: (context, menuConstraints) {
        final menuWidth = menuConstraints.maxWidth;
        return SizedBox(
          height: 44,
          child: PopupMenuButton<String>(
            tooltip: 'تصفية حسب الفرع',
            offset: const Offset(0, 48),
            constraints: BoxConstraints(
              minWidth: menuWidth,
              maxWidth: menuWidth,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            color: colorScheme.surfaceContainerHigh,
            elevation: 3,
            onSelected: (val) => setState(() => _selectedBranch = val),
            itemBuilder: (context) {
              return [
                _buildM3MenuItem(
                  value: 'all',
                  label: 'جميع الفروع',
                  count: totalPhotos,
                  icon: Icons.storefront_rounded,
                  isSelected: !isFiltered,
                  colorScheme: colorScheme,
                  accentColor: !isFiltered ? colorScheme.primary : null,
                ),
                ...sortedBranches.map((b) {
                  final isSelected = _selectedBranch == b;
                  return _buildM3MenuItem(
                    value: b,
                    label: b,
                    count: branchCounts[b],
                    icon: Icons.storefront_outlined,
                    isSelected: isSelected,
                    colorScheme: colorScheme,
                    accentColor: isSelected ? colorScheme.primary : null,
                  );
                }),
              ];
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isFiltered
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: isFiltered ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 18,
                    color: isFiltered
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isFiltered
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── M3 Delegate Filter Dropdown (Height 44dp, LayoutBuilder matching width) ──
  Widget _buildM3DelegateDropdown({
    required List<String> sortedDelegates,
    required Map<String, int> delegateCounts,
    required ColorScheme colorScheme,
    required int totalPhotos,
  }) {
    final isFiltered = _selectedDelegate != 'all';
    final currentLabel = isFiltered ? _selectedDelegate : 'جميع المناديب';

    return LayoutBuilder(
      builder: (context, menuConstraints) {
        final menuWidth = menuConstraints.maxWidth;
        return SizedBox(
          height: 44,
          child: PopupMenuButton<String>(
            tooltip: 'تصفية حسب المناديب',
            offset: const Offset(0, 48),
            constraints: BoxConstraints(
              minWidth: menuWidth,
              maxWidth: menuWidth,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            color: colorScheme.surfaceContainerHigh,
            elevation: 3,
            onSelected: (val) => setState(() => _selectedDelegate = val),
            itemBuilder: (context) {
              return [
                _buildM3MenuItem(
                  value: 'all',
                  label: 'جميع المناديب',
                  count: totalPhotos,
                  icon: Icons.person_rounded,
                  isSelected: !isFiltered,
                  colorScheme: colorScheme,
                  accentColor: !isFiltered ? colorScheme.primary : null,
                ),
                ...sortedDelegates.map((d) {
                  final isSelected = _selectedDelegate == d;
                  return _buildM3MenuItem(
                    value: d,
                    label: d,
                    count: delegateCounts[d],
                    icon: Icons.person_outline_rounded,
                    isSelected: isSelected,
                    colorScheme: colorScheme,
                    accentColor: isSelected ? colorScheme.primary : null,
                  );
                }),
              ];
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isFiltered
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: isFiltered ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: isFiltered
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isFiltered
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── M3 Menu Item with Counter Pill and Checkmark ──
  PopupMenuItem<String> _buildM3MenuItem({
    required String value,
    required String label,
    required int? count,
    required IconData icon,
    required bool isSelected,
    required ColorScheme colorScheme,
    Color? accentColor,
  }) {
    final effectiveColor = accentColor ??
        (isSelected ? colorScheme.primary : colorScheme.onSurface);

    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: effectiveColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (isSelected)
            Icon(
              Icons.check_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // TAB 1: أذونات التصوير مع الفلترة حسب الحالة وتفاصيل الإذن
  // ─────────────────────────────────────────────────────────
  Widget _buildPermissionsList(
    List<PhotoPermission> permissions,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final activeList = permissions.where((p) {
      return p.status.toLowerCase() == 'approved' && !p.endDate.isBefore(todayStart);
    }).toList();

    final pendingList = permissions.where((p) {
      return p.status.toLowerCase() == 'pending';
    }).toList();

    final expiredList = permissions.where((p) {
      final isApproved = p.status.toLowerCase() == 'approved';
      return (isApproved && p.endDate.isBefore(todayStart)) || p.status.toLowerCase() == 'rejected';
    }).toList();

    // Filter by selected tab chip
    List<PhotoPermission> baseList = permissions;
    if (_selectedPermissionFilter == 'active') {
      baseList = activeList;
    } else if (_selectedPermissionFilter == 'pending') {
      baseList = pendingList;
    } else if (_selectedPermissionFilter == 'expired') {
      baseList = expiredList;
    }

    final query = _searchController.text.trim().toLowerCase();
    final filtered = baseList.where((p) {
      if (query.isNotEmpty) {
        final matchesBranch = p.branchNames.any((b) => b.toLowerCase().contains(query));
        final matchesCode = (p.companyCode?.toString() ?? '').toLowerCase().contains(query);
        final matchesDept = (p.department ?? '').toLowerCase().contains(query);
        if (!matchesBranch && !matchesCode && !matchesDept) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Search & Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 1.0,
              ),
            ),
          ),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 768;

                  final searchBar = _buildPhotosSearchBar(
                    colorScheme,
                    hintText: 'بحث باسم الفرع أو كود الإذن أو القسم...',
                  );

                  final filterGroup = TashilConnectedButtonGroup<String>(
                    height: 44,
                    isScrollable: true,
                    selectedValue: _selectedPermissionFilter,
                    items: [
                      TashilConnectedButtonItem(
                        value: 'all',
                        label: 'الكل (${permissions.length})',
                        icon: Icons.filter_list_rounded,
                      ),
                      TashilConnectedButtonItem(
                        value: 'active',
                        label: 'النشطة (${activeList.length})',
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      TashilConnectedButtonItem(
                        value: 'pending',
                        label: 'المعلقة (${pendingList.length})',
                        icon: Icons.hourglass_top_rounded,
                      ),
                      TashilConnectedButtonItem(
                        value: 'expired',
                        label: 'المنتهية (${expiredList.length})',
                        icon: Icons.event_busy_rounded,
                      ),
                    ],
                    onSelected: (val) {
                      setState(() => _selectedPermissionFilter = val);
                    },
                  );

                  if (isDesktop) {
                    return Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: searchBar,
                        ),
                        const SizedBox(width: 12),
                        filterGroup,
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchBar,
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: filterGroup,
                      ),
                    ],
                  );
                },
              ),

              // Summary & Clear Filters Bar
              if (_selectedPermissionFilter != 'all' || _searchController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'النتائج المعروضة: ${filtered.length} من أصل ${permissions.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedPermissionFilter = 'all';
                          _searchController.clear();
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

        // List Content
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 56,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        permissions.isEmpty
                            ? 'لا توجد أذونات تصوير مسجلة للشركة حالياً'
                            : 'لا توجد أذونات مطابقة للبحث أو الفلتر المختار',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _showCreateRequestSheet(context),
                        icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                        label: const Text('إرسال طلب إذن تصوير جديد'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => _refreshData(),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 750) {
                        return GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 550,
                            childAspectRatio: 1.85,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => _buildPermissionCard(
                            filtered[index],
                            theme,
                            colorScheme,
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _buildPermissionCard(
                          filtered[index],
                          theme,
                          colorScheme,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }


  Widget _buildPermissionCard(
    PhotoPermission perm,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final isApproved = perm.status.toLowerCase() == 'approved';
    final isPending = perm.status.toLowerCase() == 'pending';
    final isExpired = isApproved && perm.endDate.isBefore(todayStart);
    final isActive = isApproved && !perm.endDate.isBefore(todayStart);

    final daysCount = perm.endDate.difference(perm.startDate).inDays;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive
              ? const Color(0xFF2E7D32).withValues(alpha: 0.4)
              : isPending
                  ? Colors.orange.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Icon + Company/Branch + Status Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                        : isPending
                            ? Colors.orange.withValues(alpha: 0.12)
                            : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isActive
                        ? Icons.verified_rounded
                        : isPending
                            ? Icons.hourglass_top_rounded
                            : Icons.assignment_outlined,
                    color: isActive
                        ? const Color(0xFF2E7D32)
                        : isPending
                            ? Colors.orange.shade800
                            : colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        perm.companyName.isNotEmpty ? perm.companyName : 'إذن تصوير',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'الفترة المصرحة ($daysCount يوم): من ${DateFormat('yyyy/MM/dd').format(perm.startDate)} إلى ${DateFormat('yyyy/MM/dd').format(perm.endDate)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isActive
                            ? const Color(0xFF2E7D32)
                            : isPending
                                ? Colors.orange
                                : isExpired
                                    ? Colors.red
                                    : colorScheme.outline)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive
                        ? 'نشط ومصرح'
                        : isPending
                            ? 'قيد المراجعة'
                            : isExpired
                                ? 'منتهي'
                                : 'مرفوض',
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFF2E7D32)
                          : isPending
                              ? Colors.orange.shade800
                              : isExpired
                                  ? Colors.red.shade800
                                  : colorScheme.outline,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // Department Chip
            if (perm.department != null && perm.department!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.category_rounded, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'القسم: ${perm.department}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Branches
            const SizedBox(height: 8),
            Text(
              'الفروع المعتمدة (${perm.branchNames.length}):',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            _HRBranchNamesList(branchNames: perm.branchNames),

            const Spacer(),
            const Divider(height: 16),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isPending)
                  TextButton.icon(
                    onPressed: () => _confirmCancelPermission(perm),
                    icon: Icon(Icons.cancel_outlined, size: 16, color: colorScheme.error),
                    label: Text(
                      'إلغاء الطلب',
                      style: TextStyle(color: colorScheme.error, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CapturedPhotosViewScreen(photoPermission: perm),
                      ),
                    );
                  },
                  icon: const Icon(Icons.collections_rounded, size: 16),
                  label: const Text('عرض صور هذا الإذن', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// ويدجت عرض أسماء الفروع مع خاصية الطي/التوسيع
// ─────────────────────────────────────────────────────────
class _HRBranchNamesList extends StatefulWidget {
  final List<String> branchNames;

  const _HRBranchNamesList({required this.branchNames});

  @override
  State<_HRBranchNamesList> createState() => _HRBranchNamesListState();
}

class _HRBranchNamesListState extends State<_HRBranchNamesList> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.branchNames.isEmpty
        ? 'جميع فروع الشركة'
        : widget.branchNames.join('، ');

    return GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            maxLines: _isExpanded ? null : 2,
            overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (text.length > 60 || widget.branchNames.length > 3) ...[
            const SizedBox(height: 2),
            Text(
              _isExpanded ? 'عرض أقل ▲' : 'عرض المزيد (${widget.branchNames.length} فروع)... ▼',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// شيت إرسال طلب إذن تصوير جديد لمسؤولي الموارد البشرية
// ─────────────────────────────────────────────────────────
class _HRCreatePhotoRequestBottomSheet extends StatefulWidget {
  final Delegate hrDelegate;
  final PhotoPermissionBloc photoBloc;

  const _HRCreatePhotoRequestBottomSheet({
    required this.hrDelegate,
    required this.photoBloc,
  });

  @override
  State<_HRCreatePhotoRequestBottomSheet> createState() =>
      _HRCreatePhotoRequestBottomSheetState();
}

class _HRCreatePhotoRequestBottomSheetState
    extends State<_HRCreatePhotoRequestBottomSheet> {
  late DateTime _startDate;
  late DateTime _endDate;
  String? _selectedDepartment;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _endDate = DateTime.now().add(const Duration(days: 30));
    _selectedDepartment = kPhotoPermissionDepartments.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    return Material(
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          top: 24,
          left: 24,
          right: 24,
          bottom: media.viewInsets.bottom + 24,
        ),
        child: BlocBuilder<BranchBloc, BranchState>(
          builder: (context, state) {
            List<Branch> branches = [];
            if (state is BranchLoaded) {
              branches = state.branches;
            }
            final isLoadingBranches = state is BranchLoading;

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'إرسال طلب إذن تصوير جديد',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 12),

                  // القسم المطلوب للتصوير
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.category_rounded, color: colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'القسم المطلوب للتصوير:',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedDepartment,
                          isExpanded: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: colorScheme.surface,
                          ),
                          items: kPhotoPermissionDepartments.map((dept) {
                            return DropdownMenuItem<String>(
                              value: dept,
                              child: Text(
                                dept,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedDepartment = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // كارت مدة الإذن (30 يوم)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.timer_rounded, color: colorScheme.primary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'مدة إذن التصوير:',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'شهر واحد (30 يوم)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              'تاريخ البداية: ${DateFormat('yyyy-MM-dd').format(_startDate)}',
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.event_available_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              'تاريخ النهاية: ${DateFormat('yyyy-MM-dd').format(_endDate)}',
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // كارت نطاق الفروع
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.store_rounded, color: colorScheme.secondary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'نطاق الفروع:',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (isLoadingBranches)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'جميع الفروع (${branches.length})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'سيتم تطبيق إذن التصوير تلقائياً على كافة فروع الشركة المعتمدة.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // زر الإرسال
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: (isLoadingBranches || branches.isEmpty)
                        ? null
                        : () {
                            widget.photoBloc.add(
                                  RequestPermissionRequested(
                                    organizationUID: widget.hrDelegate.organizationUID,
                                    companyUID: widget.hrDelegate.companyUID,
                                    companyName: widget.hrDelegate.companyName,
                                    companyCode: null,
                                    branchIds: branches.map((b) => b.id).toList(),
                                    branchNames: branches.map((b) => b.branchName).toList(),
                                    startDate: _startDate,
                                    endDate: _endDate,
                                    requestedBy: widget.hrDelegate.uid,
                                    department: _selectedDepartment,
                                  ),
                                );
                            Navigator.pop(context);
                          },
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text(
                      'إرسال الطلب للاعتماد (شامل كل الفروع)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
