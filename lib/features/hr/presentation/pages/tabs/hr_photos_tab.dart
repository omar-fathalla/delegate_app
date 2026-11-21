import 'package:flutter/material.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:delegate_app/core/widgets/branch_name_label.dart';
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
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_adaptive_sheet.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';

/// The two views of the «الصور» page.
enum HrPhotosView { photos, permissions }

/// Lets the web HR shell switch an open «الصور» page to one of its views.
///
/// TAS-149: photo permissions live only inside «الصور». Old entry points of
/// the retired «أذونات التصوير» page call [show] with
/// [HrPhotosView.permissions]. Every call notifies, even when the same view
/// is requested twice.
class HrPhotosViewController extends ChangeNotifier {
  HrPhotosView? _requested;

  /// Last requested view, read by a page that mounts after the request.
  HrPhotosView? get requested => _requested;

  void show(HrPhotosView view) {
    _requested = view;
    notifyListeners();
  }
}

class HRPhotosTab extends StatefulWidget {
  final Delegate hrDelegate;

  /// View shown first. A pending [viewController] request wins.
  final HrPhotosView initialView;

  /// Web shell only: switches the view while the page stays mounted.
  final HrPhotosViewController? viewController;

  const HRPhotosTab({
    super.key,
    required this.hrDelegate,
    this.initialView = HrPhotosView.photos,
    this.viewController,
  });

  @override
  State<HRPhotosTab> createState() => HRPhotosTabState();
}

class HRPhotosTabState extends State<HRPhotosTab> {
  int _selectedView = 0; // 0 = الصور الميدانية, 1 = أذونات التصوير
  final TextEditingController _searchController = TextEditingController();

  /// Last loaded permissions, for the web toolbar filter counts.
  List<PhotoPermission> _cachedPermissions = [];

  // Filters for View 0 (الصور الميدانية)
  String _selectedBranch = 'all';
  String _selectedDelegate = 'all';

  // Filters for View 1 (أذونات التصوير)
  String _selectedPermissionFilter = 'all'; // all, active, pending, expired

  late PhotoPermissionBloc _photoBloc;
  List<CapturedPhoto> _cachedPhotos = [];

  @override
  void initState() {
    super.initState();
    _photoBloc = di.sl<PhotoPermissionBloc>();
    final view = widget.viewController?.requested ?? widget.initialView;
    _selectedView = view == HrPhotosView.permissions ? 1 : 0;
    widget.viewController?.addListener(_onViewRequested);
    _refreshData();
  }

  @override
  void didUpdateWidget(covariant HRPhotosTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewController != widget.viewController) {
      oldWidget.viewController?.removeListener(_onViewRequested);
      widget.viewController?.addListener(_onViewRequested);
    }
  }

  void _onViewRequested() {
    final view = widget.viewController?.requested;
    if (!mounted || view == null) return;
    _selectView(view == HrPhotosView.permissions ? 1 : 0);
  }

  /// Switches between the photos and permissions views and reloads.
  void _selectView(int view) {
    if (view == _selectedView) return;
    setState(() {
      _selectedView = view;
      _selectedBranch = 'all';
      _selectedDelegate = 'all';
      _selectedPermissionFilter = 'all';
      _searchController.clear();
    });
    _refreshData();
  }

  @override
  void dispose() {
    widget.viewController?.removeListener(_onViewRequested);
    _searchController.dispose();
    _photoBloc.close();
    super.dispose();
  }

  /// Exposes refresh capability to parent screen AppBar or header controls
  void refreshData() {
    _refreshData();
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
          SnackBar(
            content: Text(
              '⚠️ يوجد بالفعل إذن تصوير فعال أو معلق قيد المراجعة لهذه الشركة. لا يمكن تقديم طلب جديد حتى انتهاء الإذن الحالي.',
            ),
            backgroundColor: HrStatusColors.of(context).warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // TAS-150: the web opens the request as a dialog (a bottom sheet on a
    // narrow window). Mobile keeps its own bottom sheet below.
    if (WebRuntimePolicy.isWeb) {
      showHrAdaptiveSheet<void>(
        context: context,
        title: 'طلب إذن تصوير',
        dialogWidth: 640,
        scrollBody: false,
        builder: (sheetContext) => MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => di.sl<BranchBloc>()..add(BranchLoadRequested()),
            ),
            BlocProvider.value(value: _photoBloc),
          ],
          child: _HRCreatePhotoRequestBottomSheet(
            hrDelegate: widget.hrDelegate,
            photoBloc: _photoBloc,
            framed: true,
          ),
        ),
      );
      return;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: HrStatusColors.of(context).danger, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تأكيد حذف الصورة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.titleMedium),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من حذف هذه الصورة المرسلة من المندوب "${photo.delegateName}" بفرع "${BranchDisplayCache.instance.displayName(photo.branchName)}"؟',
              style: const TextStyle(fontSize: HrFont.body),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(HrRadius.chip),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: HrStatusColors.of(context).danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم حذف الصورة بشكل نهائي من قاعدة البيانات ومساحة التخزين.',
                      style: TextStyle(fontSize: HrFont.labelMedium, color: HrStatusColors.of(context).danger),
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
              backgroundColor: HrStatusColors.of(context).danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.chip)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
        title: const Text('إلغاء طلب إذن التصوير'),
        content: const Text('هل أنت متأكد من رغبتك في إلغاء هذا الطلب المعلق؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HrStatusColors.of(context).danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.chip)),
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
                          fontSize: HrFont.titleMedium,
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
                      borderRadius: BorderRadius.circular(HrRadius.card),
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
                      borderRadius: BorderRadius.circular(HrRadius.card),
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
                              photo.branchName.isNotEmpty ? BranchDisplayCache.instance.displayName(photo.branchName) : 'الفرع غير محدد',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: HrFont.body,
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
                                fontSize: HrFont.labelMedium,
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
                              fontSize: HrFont.body,
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
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
                        borderRadius: BorderRadius.circular(HrRadius.chip),
                      ),
                      child: Text(
                        statusText!,
                        style: TextStyle(
                          color: saveSuccess ? colorScheme.onPrimaryContainer : colorScheme.onErrorContainer,
                          fontSize: HrFont.labelMedium,
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
                backgroundColor: HrStatusColors.of(context).success,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _refreshData();
          } else if (state is PhotoPermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: HrStatusColors.of(context).success,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _refreshData();
          } else if (state is PhotoPermissionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: HrStatusColors.of(context).danger,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is CapturedPhotosLoaded) {
            _cachedPhotos = state.photos;
          }
          if (state is PhotoPermissionsLoaded) {
            _cachedPermissions = state.permissions;
          }

          final currentPhotos = (state is CapturedPhotosLoaded)
              ? state.photos
              : _cachedPhotos;

          final uniqueBranches = <String>{};
          final uniqueDelegates = <String>{};
          final branchCounts = <String, int>{};
          final delegateCounts = <String, int>{};

          for (final p in currentPhotos) {
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

          return Column(
            children: [
              // ── Top Header with M3 2-Row Control Bar ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                child: WebRuntimePolicy.isWeb
                    ? _buildWebToolbar(
                        colorScheme: colorScheme,
                        sortedBranches: sortedBranches,
                        branchCounts: branchCounts,
                        sortedDelegates: sortedDelegates,
                        delegateCounts: delegateCounts,
                        totalPhotos: currentPhotos.length,
                      )
                    : LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 768;

                    final actionButtonsGroup = _buildM3ActionButtonsGroup(colorScheme, height: 40);

                    final buttonGroup = TashilConnectedButtonGroup<int>(
                      isScrollable: false,
                      height: 36,
                      itemPadding: const EdgeInsets.symmetric(horizontal: 10),
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

                    final branchDropdown = _buildM3BranchDropdown(
                      sortedBranches: sortedBranches,
                      branchCounts: branchCounts,
                      colorScheme: colorScheme,
                      totalPhotos: currentPhotos.length,
                      height: 40,
                    );

                    final delegateDropdown = _buildM3DelegateDropdown(
                      sortedDelegates: sortedDelegates,
                      delegateCounts: delegateCounts,
                      colorScheme: colorScheme,
                      totalPhotos: currentPhotos.length,
                      height: 36,
                    );

                    if (_selectedView == 0) {
                      // TAB 0: الصور الميدانية
                      // Row 1: طلب إذن تصوير + التقرير الشهري مع جميع الفروع
                      // Row 2: الصور الميدانية + أذونات التصوير مع جميع المناديب
                      if (isDesktop) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                actionButtonsGroup,
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 240,
                                  child: branchDropdown,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                buttonGroup,
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 240,
                                  child: delegateDropdown,
                                ),
                              ],
                            ),
                          ],
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              actionButtonsGroup,
                              const SizedBox(width: 8),
                              Expanded(child: branchDropdown),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              buttonGroup,
                              const SizedBox(width: 8),
                              Expanded(child: delegateDropdown),
                            ],
                          ),
                        ],
                      );
                    } else {
                      // TAB 1: أذونات التصوير
                      if (isDesktop) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            buttonGroup,
                            actionButtonsGroup,
                          ],
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              actionButtonsGroup,
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              buttonGroup,
                            ],
                          ),
                        ],
                      );
                    }
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
    final filtered = photos.where((p) {
      if (_selectedBranch != 'all' && p.branchName != _selectedBranch) {
        return false;
      }
      if (_selectedDelegate != 'all' && p.delegateName != _selectedDelegate) {
        return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty && WebRuntimePolicy.isWeb) {
      final isFiltered = _selectedBranch != 'all' || _selectedDelegate != 'all';
      return HrEmptyState(
        key: const ValueKey('hr_photos_empty'),
        icon: Icons.photo_library_outlined,
        title: photos.isEmpty
            ? 'لا توجد صور ميدانية'
            : 'لا توجد صور مطابقة للفلتر',
        message: photos.isEmpty
            ? 'ستظهر هنا الصور التي يلتقطها المناديب أثناء الزيارات.'
            : null,
        action: isFiltered
            ? TextButton(
                onPressed: () => setState(() {
                  _selectedBranch = 'all';
                  _selectedDelegate = 'all';
                }),
                child: const Text('إظهار الكل'),
              )
            : null,
      );
    }

    if (filtered.isEmpty) {
      return Center(
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
                  : 'لا توجد صور معاينة ميدانية مطابقة للفلتر',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_selectedBranch != 'all' || _selectedDelegate != 'all') ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _selectedBranch = 'all';
                    _selectedDelegate = 'all';
                  });
                },
                child: const Text('إلغاء الفلاتر وإظهار الكل'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
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
            borderRadius: BorderRadius.circular(HrRadius.card),
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HrRadius.card),
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
                            fontSize: HrFont.body,
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
                              child: BranchNameLabel(
                                branchName: photo.branchName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: HrFont.labelSmall,
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
                            fontSize: HrFont.labelSmall,
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
    );
  }

  // ── M3 Connected Action Button Group (طلب إذن تصوير + التقرير الشهري) ──
  Widget _buildM3ActionButtonsGroup(ColorScheme colorScheme, {double height = 40}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(height / 2),
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
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_a_photo_rounded,
                      size: 15,
                      color: colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'طلب إذن تصوير',
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
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
              onTap: _openMonthlyReport,
              hoverColor: colorScheme.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 15,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'التقرير الشهري',
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
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

  /// Opens «التقرير الشهري».
  ///
  /// TAS-150: inside the wide web shell it is an inner page (breadcrumb,
  /// sidebar kept, wide content width) without its own app bar. Without a
  /// shell host (mobile, narrow web) [pushHrInnerPage] pushes it full screen
  /// with its app bar, as before.
  void _openMonthlyReport() {
    pushHrInnerPage<void>(
      context,
      title: 'التقرير الشهري',
      maxWidth: HrInnerPageWidth.wide,
      builder: (_, inShell) => BlocProvider(
        create: (_) => di.sl<PhotoPermissionBloc>(),
        child: MonthlyPhotoReportScreen(
          delegate: widget.hrDelegate,
          showAppBar: !inShell,
        ),
      ),
    );
  }

  /// Active, pending and expired (or rejected) permissions.
  ({
    List<PhotoPermission> active,
    List<PhotoPermission> pending,
    List<PhotoPermission> expired,
  })
  _permissionBuckets(List<PhotoPermission> permissions) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return (
      active: permissions.where((p) {
        return p.status.toLowerCase() == 'approved' &&
            !p.endDate.isBefore(todayStart);
      }).toList(),
      pending: permissions.where((p) {
        return p.status.toLowerCase() == 'pending';
      }).toList(),
      expired: permissions.where((p) {
        final isApproved = p.status.toLowerCase() == 'approved';
        return (isApproved && p.endDate.isBefore(todayStart)) ||
            p.status.toLowerCase() == 'rejected';
      }).toList(),
    );
  }

  /// Web toolbar (TAS-149, TAS-150): one line, same order on both views.
  ///
  /// View switch at the start, the filters of the current view in the
  /// middle, and the two page actions («التقرير الشهري», then the one
  /// «طلب إذن تصوير» button) pinned at the end so nothing moves when the
  /// view changes.
  Widget _buildWebToolbar({
    required ColorScheme colorScheme,
    required List<String> sortedBranches,
    required Map<String, int> branchCounts,
    required List<String> sortedDelegates,
    required Map<String, int> delegateCounts,
    required int totalPhotos,
  }) {
    const filterWidth = 220.0;
    const controlHeight = 40.0;

    final viewSwitch = TashilConnectedButtonGroup<int>(
      key: const ValueKey('hr_photos_view_switch'),
      isScrollable: false,
      height: controlHeight,
      itemPadding: const EdgeInsets.symmetric(horizontal: 12),
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
      onSelected: _selectView,
    );

    final List<Widget> filters;
    if (_selectedView == 0) {
      filters = [
        SizedBox(
          width: filterWidth,
          child: _buildM3BranchDropdown(
            sortedBranches: sortedBranches,
            branchCounts: branchCounts,
            colorScheme: colorScheme,
            totalPhotos: totalPhotos,
            height: controlHeight,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: filterWidth,
          child: _buildM3DelegateDropdown(
            sortedDelegates: sortedDelegates,
            delegateCounts: delegateCounts,
            colorScheme: colorScheme,
            totalPhotos: totalPhotos,
            height: controlHeight,
          ),
        ),
      ];
    } else {
      final buckets = _permissionBuckets(_cachedPermissions);
      filters = [
        TashilConnectedButtonGroup<String>(
          key: const ValueKey('hr_photos_permission_filter'),
          height: controlHeight,
          isScrollable: false,
          selectedValue: _selectedPermissionFilter,
          items: [
            TashilConnectedButtonItem(
              value: 'all',
              label: 'الكل (${_cachedPermissions.length})',
              icon: Icons.filter_list_rounded,
            ),
            TashilConnectedButtonItem(
              value: 'active',
              label: 'النشطة (${buckets.active.length})',
              icon: Icons.check_circle_outline_rounded,
            ),
            TashilConnectedButtonItem(
              value: 'pending',
              label: 'المعلقة (${buckets.pending.length})',
              icon: Icons.hourglass_top_rounded,
            ),
            TashilConnectedButtonItem(
              value: 'expired',
              label: 'المنتهية (${buckets.expired.length})',
              icon: Icons.event_busy_rounded,
            ),
          ],
          onSelected: (val) => setState(() => _selectedPermissionFilter = val),
        ),
      ];
    }

    return Row(
      key: const ValueKey('hr_photos_toolbar'),
      children: [
        viewSwitch,
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: filters),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          key: const ValueKey('hr_photos_monthly_report'),
          onPressed: _openMonthlyReport,
          icon: const Icon(Icons.calendar_month_rounded, size: 18),
          label: const Text('التقرير الشهري'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('hr_photos_request_permission'),
          onPressed: () => _showCreateRequestSheet(context),
          icon: const Icon(Icons.add_a_photo_rounded, size: 18),
          label: const Text('طلب إذن تصوير'),
        ),
      ],
    );
  }

  // ── M3 Branch Filter Dropdown ──
  Widget _buildM3BranchDropdown({
    required List<String> sortedBranches,
    required Map<String, int> branchCounts,
    required ColorScheme colorScheme,
    required int totalPhotos,
    double height = 40,
  }) {
    final isFiltered = _selectedBranch != 'all';
    final currentLabel = isFiltered ? _selectedBranch : 'جميع الفروع';

    return LayoutBuilder(
      builder: (context, menuConstraints) {
        final menuWidth = menuConstraints.maxWidth.clamp(180.0, 320.0);
        return SizedBox(
          height: height,
          child: PopupMenuButton<String>(
            tooltip: 'تصفية حسب الفرع',
            offset: Offset(0, height + 4),
            constraints: BoxConstraints(
              minWidth: menuWidth,
              maxWidth: 320,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HrRadius.card),
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
                    label: BranchDisplayCache.instance.displayName(b),
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
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(height / 2),
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
                    size: 16,
                    color: isFiltered
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      currentLabel,
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
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
                    size: 18,
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

  // ── M3 Delegate Filter Dropdown ──
  Widget _buildM3DelegateDropdown({
    required List<String> sortedDelegates,
    required Map<String, int> delegateCounts,
    required ColorScheme colorScheme,
    required int totalPhotos,
    double height = 36,
  }) {
    final isFiltered = _selectedDelegate != 'all';
    final currentLabel = isFiltered ? _selectedDelegate : 'جميع المناديب';

    return LayoutBuilder(
      builder: (context, menuConstraints) {
        final menuWidth = menuConstraints.maxWidth.clamp(180.0, 320.0);
        return SizedBox(
          height: height,
          child: PopupMenuButton<String>(
            tooltip: 'تصفية حسب المناديب',
            offset: Offset(0, height + 4),
            constraints: BoxConstraints(
              minWidth: menuWidth,
              maxWidth: 320,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HrRadius.card),
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
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(height / 2),
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
                    size: 16,
                    color: isFiltered
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      currentLabel,
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
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
                    size: 18,
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
                fontSize: HrFont.body,
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
                borderRadius: BorderRadius.circular(HrRadius.chip),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: HrFont.labelSmall,
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
    final buckets = _permissionBuckets(permissions);
    final activeList = buckets.active;
    final pendingList = buckets.pending;
    final expiredList = buckets.expired;

    // Filter by selected tab chip
    List<PhotoPermission> baseList = permissions;
    if (_selectedPermissionFilter == 'active') {
      baseList = activeList;
    } else if (_selectedPermissionFilter == 'pending') {
      baseList = pendingList;
    } else if (_selectedPermissionFilter == 'expired') {
      baseList = expiredList;
    }

    final filtered = baseList;

    // TAS-149: on the web the status filter sits in the page toolbar, and
    // the one request button is the toolbar's, so the empty state has no
    // button of its own.
    if (WebRuntimePolicy.isWeb) {
      if (filtered.isEmpty) {
        return HrEmptyState(
          key: const ValueKey('hr_photos_permissions_empty'),
          icon: Icons.assignment_outlined,
          title: permissions.isEmpty
              ? 'لا توجد أذونات تصوير'
              : 'لا توجد أذونات مطابقة للفلتر',
          message: permissions.isEmpty
              ? 'لطلب إذن جديد استخدم زر «طلب إذن تصوير» في أعلى الصفحة.'
              : null,
          action: permissions.isEmpty
              ? null
              : TextButton(
                  onPressed: () =>
                      setState(() => _selectedPermissionFilter = 'all'),
                  child: const Text('إظهار الكل'),
                ),
        );
      }
      return _buildPermissionsGrid(filtered, theme, colorScheme);
    }

    return Column(
      children: [
        // Filter Bar
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

                  final filterGroup = TashilConnectedButtonGroup<String>(
                    height: 40,
                    isScrollable: false,
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
                        filterGroup,
                      ],
                    );
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: filterGroup,
                  );
                },
              ),

              // Summary & Clear Filters Bar
              if (_selectedPermissionFilter != 'all') ...[
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
                            : 'لا توجد أذونات مطابقة للفلتر المختار',
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
              : _buildPermissionsGrid(filtered, theme, colorScheme),
        ),
      ],
    );
  }

  /// Permission cards: a grid on wide layouts, a list on narrow ones.
  Widget _buildPermissionsGrid(
    List<PhotoPermission> filtered,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return RefreshIndicator(
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
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(
          color: isActive
              ? HrStatusColors.of(context).success.withValues(alpha: 0.4)
              : isPending
                  ? Colors.orange.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Icon + Company/Branch + Status Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? HrStatusColors.of(context).success.withValues(alpha: 0.12)
                        : isPending
                            ? Colors.orange.withValues(alpha: 0.12)
                            : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(HrRadius.chip),
                  ),
                  child: Icon(
                    isActive
                        ? Icons.verified_rounded
                        : isPending
                            ? Icons.hourglass_top_rounded
                            : Icons.assignment_outlined,
                    color: isActive
                        ? HrStatusColors.of(context).success
                        : isPending
                            ? HrStatusColors.of(context).warning
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
                            ? HrStatusColors.of(context).success
                            : isPending
                                ? HrStatusColors.of(context).warning
                                : isExpired
                                    ? HrStatusColors.of(context).danger
                                    : colorScheme.outline)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(HrRadius.button),
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
                          ? HrStatusColors.of(context).success
                          : isPending
                              ? HrStatusColors.of(context).warning
                              : isExpired
                                  ? HrStatusColors.of(context).danger
                                  : colorScheme.outline,
                      fontSize: HrFont.labelSmall,
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
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.category_rounded, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'القسم: ${perm.department}',
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
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

            const SizedBox(height: 12),
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
                      style: TextStyle(color: colorScheme.error, fontSize: HrFont.labelMedium, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
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
                  label: const Text('عرض صور هذا الإذن', style: TextStyle(fontSize: HrFont.labelMedium)),
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
        : widget.branchNames.map(BranchDisplayCache.instance.displayName).join('، ');

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
            style: theme.textTheme.bodySmall?.copyWith(fontSize: HrFont.labelMedium),
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
                fontSize: HrFont.labelSmall,
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

  /// True inside [showHrAdaptiveSheet] on the web: no own title row,
  /// background or padding.
  final bool framed;

  const _HRCreatePhotoRequestBottomSheet({
    required this.hrDelegate,
    required this.photoBloc,
    this.framed = false,
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

    // Web dialog: [HrSheetFrame] draws the title, close button and padding,
    // so the sheet chrome below turns into a plain pass-through.
    final framed = widget.framed;
    return Material(
      type: framed ? MaterialType.transparency : MaterialType.canvas,
      color: framed ? null : colorScheme.surface,
      borderRadius: framed ? null : const BorderRadius.vertical(top: Radius.circular(HrRadius.pill)),
      clipBehavior: framed ? Clip.none : Clip.antiAlias,
      child: Padding(
        padding: framed
            ? EdgeInsets.zero
            : EdgeInsets.only(
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
                  if (!framed) ...[
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
                  ],

                  // القسم المطلوب للتصوير
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(HrRadius.card),
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
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
                            filled: true,
                            fillColor: colorScheme.surface,
                          ),
                          items: kPhotoPermissionDepartments.map((dept) {
                            return DropdownMenuItem<String>(
                              value: dept,
                              child: Text(
                                dept,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: HrFont.body),
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
                      borderRadius: BorderRadius.circular(HrRadius.card),
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
                                borderRadius: BorderRadius.circular(HrRadius.button),
                              ),
                              child: const Text(
                                'شهر واحد (30 يوم)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: HrFont.body,
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
                      borderRadius: BorderRadius.circular(HrRadius.card),
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
                                  borderRadius: BorderRadius.circular(HrRadius.button),
                                ),
                                child: Text(
                                  'جميع الفروع (${branches.length})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: HrFont.body,
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.titleMedium),
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
