import 'package:delegate_app/l10n/app_localizations.dart';
import 'dart:io';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import '../../data/services/photo_watermark.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/captured_photo_full_screen_viewer.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';

class DelegateCameraCaptureScreen extends StatefulWidget {
  final Delegate delegate;
  final PhotoPermission? initialPermission;

  const DelegateCameraCaptureScreen({
    super.key,
    required this.delegate,
    this.initialPermission,
  });

  @override
  State<DelegateCameraCaptureScreen> createState() => _DelegateCameraCaptureScreenState();
}

class _DelegateCameraCaptureScreenState extends State<DelegateCameraCaptureScreen> {
  List<PhotoPermission>? _cachedPermissions;
  PhotoPermission? _selectedPermission;
  String? _selectedBranchId;
  String? _selectedBranchName;
  /// TAS-302: each shot keeps the camera original, its capture time and the
  /// stamped copy (branch + date burned in). Only stamped copies are uploaded.
  final List<_StampedShot> _shots = [];
  List<File> get _capturedPhotos => [for (final s in _shots) s.stamped];
  bool _isStamping = false;
  int _selectedPhotoIndex = 0;
  final TextEditingController _commentController = TextEditingController();
  Map<String, String>? _orgBranchesMap;

  @override
  void initState() {
    super.initState();
    if (widget.initialPermission != null) {
      _selectedPermission = widget.initialPermission;
    }
    _loadOrganizationBranches();
    _loadOngoingPermissions();
  }

  Future<void> _loadOrganizationBranches() async {
    try {
      final orgUID = widget.delegate.organizationUID.trim();
      final orgName = widget.delegate.organizationName.trim().toLowerCase();

      final snapshot = await FirebaseFirestore.instance.collection('branches').get();
      final map = <String, String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final bOrgUID = (data['organizationUID'] as String?)?.trim() ?? '';
        final bOrgName = ((data['organizationName'] as String?) ??
                (data['orgName'] as String?))
            ?.trim()
            .toLowerCase() ??
            '';

        final matchUID = orgUID.isNotEmpty && bOrgUID == orgUID;
        final matchName = orgName.isNotEmpty &&
            (bOrgName == orgName ||
                bOrgName.contains(orgName) ||
                orgName.contains(bOrgName));

        if (matchUID || matchName) {
          final branchName = (data['branchName'] as String?) ??
              (data['name'] as String?) ??
              (data['title'] as String?) ??
              doc.id;
          map[doc.id] = branchName;
        }
      }

      if (mounted) {
        setState(() {
          _orgBranchesMap = map;
        });
      }
    } catch (_) {}
  }

  void _loadOngoingPermissions() {
    context.read<PhotoPermissionBloc>().add(
          LoadOngoingPermissionsRequested(
            organizationUID: widget.delegate.organizationUID,
          ),
        );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto({
    bool isAddingMore = true,
    required String branchName,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final ImagePicker picker = ImagePicker();
    try {
      // إجبار المستخدم على الكاميرا فقط لضمان مصداقية التوثيق الميداني
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50, // ضغط الصورة للأداء العالي وتوفير استهلاك البيانات
        maxWidth: 1080,
        maxHeight: 1080,
      );

      if (photo != null) {
        // Trusted (server-calibrated) clock, shown as Cairo wall time.
        final capturedAt = SubscriptionCycleHelper.cairoTime();
        final original = File(photo.path);
        setState(() => _isStamping = true);
        final shot = await _stamp(original, capturedAt, branchName);
        if (!mounted) return;
        setState(() {
          _isStamping = false;
          if (isAddingMore || _shots.isEmpty) {
            _shots.add(shot);
            _selectedPhotoIndex = _shots.length - 1;
          } else {
            _shots[_selectedPhotoIndex] = shot;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isStamping = false);
      _showErrorSnackBar(l10n.cameraOpenFailed(e));
    }
  }

  /// TAS-302: opens the selected photo on the whole screen; the viewer can
  /// ask to retake or delete it.
  Future<void> _openFullScreen(String branchName) async {
    if (_shots.isEmpty) return;
    final index = _selectedPhotoIndex;
    final action = await CapturedPhotoFullScreenViewer.open(
      context,
      photo: _shots[index].stamped,
      photoNumber: index + 1,
    );
    if (!mounted || action == null || index >= _shots.length) return;
    switch (action) {
      case CapturedPhotoViewerAction.retake:
        setState(() => _selectedPhotoIndex = index);
        await _capturePhoto(isAddingMore: false, branchName: branchName);
      case CapturedPhotoViewerAction.delete:
        _removePhotoAt(index);
    }
  }

  /// Burns [branchName] and [capturedAt] into [original]. If stamping fails
  /// the original is kept (the visit is still recorded) and the user is told.
  Future<_StampedShot> _stamp(
    File original,
    DateTime capturedAt,
    String branchName,
  ) async {
    final display = BranchDisplayCache.instance.displayName(branchName, fallback: branchName);
    try {
      final stamped = await PhotoWatermark.stampFile(
        original,
        branchName: display,
        capturedAt: capturedAt,
      );
      return _StampedShot(original, capturedAt, stamped, branchName);
    } catch (e) {
      debugPrint('TAS-302: photo stamp failed: $e');
      if (mounted) {
        _showErrorSnackBar(AppLocalizations.of(context)!.photoStampFailed);
      }
      return _StampedShot(original, capturedAt, original, branchName);
    }
  }

  /// Re-stamps every shot whose stamp names another branch (the user changed
  /// the branch after taking photos). Capture times stay as they were.
  Future<void> _restampForBranch(String branchName) async {
    if (_shots.every((s) => s.branchName == branchName)) return;
    setState(() => _isStamping = true);
    for (var i = 0; i < _shots.length; i++) {
      final shot = _shots[i];
      if (shot.branchName == branchName) continue;
      final updated = await _stamp(shot.original, shot.capturedAt, branchName);
      if (!mounted) return;
      if (i < _shots.length && identical(_shots[i], shot)) _shots[i] = updated;
    }
    if (mounted) setState(() => _isStamping = false);
  }

  void _removePhotoAt(int index) {
    if (index < 0 || index >= _capturedPhotos.length) return;
    setState(() {
      _shots.removeAt(index);
      if (_selectedPhotoIndex >= _capturedPhotos.length) {
        _selectedPhotoIndex = _capturedPhotos.isEmpty ? 0 : _capturedPhotos.length - 1;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.photoRemovedFromSession),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSupervisor = widget.delegate.role == UserRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSupervisor ? AppLocalizations.of(context)!.offerPhotosSupervisor : AppLocalizations.of(context)!.offerPhotosTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        listener: (context, state) {
          if (state is PhotoBatchUploadSuccess) {
            final isOffline = state.isOffline;
            final count = state.uploadedCount;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      isOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isOffline
                            ? AppLocalizations.of(context)!.photosSavedOffline(count)
                            : AppLocalizations.of(context)!.photosUploaded(count),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: isOffline ? Colors.orange.shade800 : Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
            setState(() {
              _shots.clear();
              _selectedPhotoIndex = 0;
              _commentController.clear();
            });
            _loadOngoingPermissions();
          } else if (state is PhotoUploadSuccess) {
            final isOffline = state.isOffline;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      isOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isOffline
                            ? AppLocalizations.of(context)!.photoSavedOffline
                            : AppLocalizations.of(context)!.photoUploaded,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: isOffline ? Colors.orange.shade800 : Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
            setState(() {
              _shots.clear();
              _selectedPhotoIndex = 0;
              _commentController.clear();
            });
            _loadOngoingPermissions();
          } else if (state is PhotoPermissionError) {
            _showErrorSnackBar(state.message);
          }
        },
        builder: (context, state) {
          if (state is OngoingPermissionsLoaded) {
            _cachedPermissions = state.permissions;
          }

          if (state is PhotoPermissionLoading && _cachedPermissions == null) {
            return Center(
              child: AppLoadingIndicator(
                style: AppLoadingStyle.threeArchedCircle,
                label: AppLocalizations.of(context)!.loadingPhotoPermissions,
              ),
            );
          }

          final permissionsToUse = _cachedPermissions ??
              (state is OngoingPermissionsLoaded ? state.permissions : null);

          if (permissionsToUse != null) {
            // تصفية الأذونات لتظهر فقط الأذونات الممنوحة لشركة المندوب / المشرف (بالـ UID، الكود، أو اسم الشركة)
            final delegatePermissions = permissionsToUse.where((p) {
              final matchUID = widget.delegate.companyUID.isNotEmpty && p.companyUID == widget.delegate.companyUID;
              final matchName = p.companyName.trim().toLowerCase() == widget.delegate.companyName.trim().toLowerCase();
              return matchUID || matchName;
            }).toList();

            if (delegatePermissions.isEmpty && widget.initialPermission == null) {
              return _buildNoPermissionsState(theme);
            }

            final availablePermissions = delegatePermissions.isNotEmpty
                ? delegatePermissions
                : (widget.initialPermission != null ? [widget.initialPermission!] : <PhotoPermission>[]);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SyncStatusBanner(),
                  // Multiple Permissions Selector (if more than 1 active permission exists)
                  if (availablePermissions.length > 1) ...[
                    DropdownButtonFormField<PhotoPermission>(
                      initialValue: _selectedPermission ?? availablePermissions.first,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.choosePhotoPermission,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.assignment_turned_in_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      ),
                      items: availablePermissions.map((p) {
                        final dept = (p.department != null && p.department!.trim().isNotEmpty)
                            ? ' (${p.department})'
                            : '';
                        return DropdownMenuItem<PhotoPermission>(
                          value: p,
                          child: Text(AppLocalizations.of(context)!.permissionOption(p.companyName, dept, p.branchNames.length)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedPermission = val;
                            _selectedBranchId = null;
                            _selectedBranchName = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Auto-selected permission/campaign info
                  ...(() {
                    final activePermission = _selectedPermission ?? availablePermissions.first;

                    // Deduplicate and sanitize branches strictly scoped to the delegate's active organization
                    final Map<String, String> uniqueBranches = {};
                    for (int i = 0; i < activePermission.branchIds.length; i++) {
                      final bId = activePermission.branchIds[i].trim();
                      if (bId.isEmpty) continue;
                      final bName = i < activePermission.branchNames.length &&
                              activePermission.branchNames[i].trim().isNotEmpty
                          ? activePermission.branchNames[i].trim()
                          : AppLocalizations.of(context)!.branchWithId(bId);

                      // If organization branches are loaded, strictly filter by delegate's active organization
                      if (_orgBranchesMap != null && _orgBranchesMap!.isNotEmpty) {
                        final matchesOrg = _orgBranchesMap!.containsKey(bId) ||
                            _orgBranchesMap!.values.any((name) =>
                                name.trim().toLowerCase() == bName.trim().toLowerCase());
                        if (!matchesOrg) {
                          continue; // Exclude branches belonging to other organizations
                        }
                      }

                      if (!uniqueBranches.containsKey(bId)) {
                        uniqueBranches[bId] = (_orgBranchesMap != null && _orgBranchesMap!.containsKey(bId))
                            ? _orgBranchesMap![bId]!
                            : bName;
                      }
                    }

                    // Fallback: If permission had all branches from an old request or none matched directly by ID,
                    // but organization branches exist, populate from the delegate's active organization branches
                    if (uniqueBranches.isEmpty && _orgBranchesMap != null && _orgBranchesMap!.isNotEmpty) {
                      uniqueBranches.addAll(_orgBranchesMap!);
                    }

                    // Sort branches alphabetically for a clean, professional user experience
                    final sortedBranches = uniqueBranches.entries.toList()
                      ..sort((a, b) => a.value.compareTo(b.value));

                    // Auto-select if there is exactly 1 branch and no branch is selected
                    String? effectiveBranchId = _selectedBranchId;
                    if (effectiveBranchId == null || !uniqueBranches.containsKey(effectiveBranchId)) {
                      if (sortedBranches.length == 1) {
                        effectiveBranchId = sortedBranches.first.key;
                      } else {
                        effectiveBranchId = null;
                      }
                    }
                    final effectiveBranchName = effectiveBranchId != null
                        ? (uniqueBranches[effectiveBranchId] ?? effectiveBranchId)
                        : null;

                    return [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.verified_rounded, color: colorScheme.primary, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context)!.offerPhotoPermissionOf(activePermission.companyName),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)!.companyLabel2(activePermission.companyName),
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (activePermission.department != null && activePermission.department!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)!.departmentLabel(activePermission.department ?? ''),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'تاريخ الإذن: من ${activePermission.startDate.toString().split(' ').first} إلى ${activePermission.endDate.toString().split(' ').first}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Branch selector dropdown or empty branch warning
                      if (sortedBranches.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.delegate.organizationName.isNotEmpty
                                      ? AppLocalizations.of(context)!.noBranchesInPermissionFor(widget.delegate.organizationName)
                                      : AppLocalizations.of(context)!.noBranchesInPermission,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey('branch_dropdown_${activePermission.uid}_${sortedBranches.length}'),
                          initialValue: effectiveBranchId,
                          decoration: InputDecoration(
                            labelText: widget.delegate.organizationName.isNotEmpty
                                ? AppLocalizations.of(context)!.chooseBranchOf(widget.delegate.organizationName)
                                : AppLocalizations.of(context)!.chooseBranchRequired,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.store_rounded),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                          ),
                          items: sortedBranches.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(BranchDisplayCache.instance.displayName(entry.value)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            final name = uniqueBranches[value] ?? value;
                            setState(() {
                              _selectedBranchId = value;
                              _selectedBranchName = name;
                            });
                            _restampForBranch(name);
                          },
                        ),

                      const SizedBox(height: 20),

                      // Camera capture preview area OR Branch selection guidance
                      if (effectiveBranchId != null) ...[
                        if (_capturedPhotos.isEmpty)
                          InkWell(
                            onTap: () => _capturePhoto(isAddingMore: true, branchName: effectiveBranchName!),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              height: 230,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                  width: 1.5,
                                  strokeAlign: BorderSide.strokeAlignInside,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      size: 46,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    AppLocalizations.of(context)!.takeOfferPhotos,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppLocalizations.of(context)!.multiPhotoHint,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonalIcon(
                                    onPressed: () => _capturePhoto(isAddingMore: true, branchName: effectiveBranchName!),
                                    icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                                    label: Text(AppLocalizations.of(context)!.takeFirstPhoto),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          // Multi-Photo Gallery Controls & Header Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.photo_library_rounded, size: 18, color: colorScheme.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${_selectedPhotoIndex + 1} / ${_capturedPhotos.length}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context)!.visitGallery,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () => _capturePhoto(isAddingMore: true, branchName: effectiveBranchName!),
                                  icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                                  label: Text(AppLocalizations.of(context)!.addPhoto),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // TAS-302: the whole photo (uncropped) so the branch/date strip
                          // is visible before sending. Tap opens it on the full screen.
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              height: 340,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: colorScheme.outlineVariant),
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: GestureDetector(
                                      key: const ValueKey('captured_photo_preview'),
                                      onTap: () => _openFullScreen(effectiveBranchName!),
                                      child: AnimatedSwitcher(
                                        duration: AppMotionDurations.medium2,
                                        switchInCurve: AppMotionCurves.emphasizedDecelerate,
                                        switchOutCurve: AppMotionCurves.emphasizedAccelerate,
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          );
                                        },
                                        child: Image.file(
                                          _capturedPhotos[_selectedPhotoIndex],
                                          key: ValueKey(_capturedPhotos[_selectedPhotoIndex].path),
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                          height: double.infinity,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Top-End Badge
                                  PositionedDirectional(
                                    top: 12,
                                    end: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.65),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        AppLocalizations.of(context)!.photoNumber(_selectedPhotoIndex + 1),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Top-Start full screen button
                                  PositionedDirectional(
                                    top: 6,
                                    start: 6,
                                    child: IconButton(
                                      key: const ValueKey('captured_photo_full_screen'),
                                      onPressed: () => _openFullScreen(effectiveBranchName!),
                                      icon: const Icon(Icons.fullscreen_rounded),
                                      tooltip: AppLocalizations.of(context)!.viewPhotoFullScreen,
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Actions under the photo, so they never cover the stamp.
                          Row(
                            children: [
                              TextButton.icon(
                                key: const ValueKey('captured_photo_retake'),
                                onPressed: () => _capturePhoto(isAddingMore: false, branchName: effectiveBranchName!),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(AppLocalizations.of(context)!.retakePhoto),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const Spacer(),
                              IconButton.filledTonal(
                                key: const ValueKey('captured_photo_delete'),
                                onPressed: () => _removePhotoAt(_selectedPhotoIndex),
                                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red.withValues(alpha: 0.8),
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                ),
                                tooltip: AppLocalizations.of(context)!.deletePhoto,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Horizontal Thumbnail Strip with M3 animated selection
                          SizedBox(
                            height: 74,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _capturedPhotos.length + 1,
                              separatorBuilder: (context, index) => const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                if (index == _capturedPhotos.length) {
                                  // Add photo thumbnail card
                                  return InkWell(
                                    onTap: () => _capturePhoto(isAddingMore: true, branchName: effectiveBranchName!),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      width: 70,
                                      height: 74,
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: colorScheme.primary.withValues(alpha: 0.5),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_a_photo_rounded, size: 22, color: colorScheme.primary),
                                          const SizedBox(height: 4),
                                          Text(
                                            AppLocalizations.of(context)!.addAction,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                final isSelected = index == _selectedPhotoIndex;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedPhotoIndex = index;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: AppMotionDurations.short3,
                                    curve: AppMotionCurves.standard,
                                    width: 70,
                                    height: 74,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                        width: isSelected ? 2.5 : 1,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: colorScheme.primary.withValues(alpha: 0.25),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.file(
                                            _capturedPhotos[index],
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                        ),
                                        PositionedDirectional(
                                          top: 4,
                                          end: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? colorScheme.primary
                                                  : Colors.black.withValues(alpha: 0.6),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${index + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Unified Comment input
                          TextField(
                            controller: _commentController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)!.visitNotesLabel(_capturedPhotos.length),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              hintText: AppLocalizations.of(context)!.visitNotesHint,
                              prefixIcon: const Icon(Icons.comment_outlined),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Batch upload status / submit button
                          if (state is PhotoBatchUploadInProgress)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AppLoadingIndicator(
                                        size: 22,
                                        color: colorScheme.primary,
                                        style: AppLoadingStyle.threeArchedCircle,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        AppLocalizations.of(context)!.uploadingPhotoXofY(state.current, state.total),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: state.total > 0 ? (state.current / state.total) : null,
                                      minHeight: 6,
                                      backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (state is PhotoPermissionUploadInProgress)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AppLoadingIndicator(
                                    size: 24,
                                    color: colorScheme.primary,
                                    style: AppLoadingStyle.threeArchedCircle,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    AppLocalizations.of(context)!.uploadingPhotosReport,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: _isStamping ? null : () async {
                                final currentPerm = _selectedPermission ?? availablePermissions.first;
                                final orgUID = currentPerm.organizationUID.isNotEmpty
                                    ? currentPerm.organizationUID
                                    : widget.delegate.organizationUID;
                                final compUID = currentPerm.companyUID.isNotEmpty
                                    ? currentPerm.companyUID
                                    : widget.delegate.companyUID;
                                final compName = currentPerm.companyName.isNotEmpty
                                    ? currentPerm.companyName
                                    : widget.delegate.companyName;
                                final compCode = currentPerm.companyCode;
                                final uploaderName = widget.delegate.role == UserRole.admin
                                    ? AppLocalizations.of(context)!.nameCompanySupervisor(widget.delegate.fullName)
                                    : widget.delegate.fullName;

                                final finalBranchId = effectiveBranchId ?? _selectedBranchId ?? '';
                                final finalBranchName = effectiveBranchName ?? _selectedBranchName ?? finalBranchId;

                                if (finalBranchId.isEmpty) {
                                  _showErrorSnackBar(AppLocalizations.of(context)!.chooseBranchFirst);
                                  return;
                                }

                                if (_capturedPhotos.isEmpty) {
                                  _showErrorSnackBar(AppLocalizations.of(context)!.takeAtLeastOnePhoto);
                                  return;
                                }

                                // TAS-302: every uploaded photo must carry the branch it is sent for.
                                await _restampForBranch(finalBranchName);
                                if (!context.mounted || _capturedPhotos.isEmpty) return;

                                context.read<PhotoPermissionBloc>().add(
                                      UploadBatchPhotosRequested(
                                        organizationUID: orgUID,
                                        companyUID: compUID,
                                        companyName: compName,
                                        companyCode: compCode,
                                        permissionId: currentPerm.uid,
                                        branchId: finalBranchId,
                                        branchName: finalBranchName,
                                        delegateUID: widget.delegate.uid,
                                        delegateName: uploaderName,
                                        imageFiles: List<File>.from(_capturedPhotos),
                                        comment: _commentController.text,
                                        latitude: 0.0,
                                        longitude: 0.0,
                                      ),
                                    );
                              },
                              icon: const Icon(Icons.cloud_upload_rounded),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              label: Text(
                                AppLocalizations.of(context)!.submitReportCount(_capturedPhotos.length),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                        ],
                      ] else ...[
                        // Guidance card when no branch is selected yet
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.store_mall_directory_rounded,
                                  size: 40,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                AppLocalizations.of(context)!.chooseBranchToStart,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AppLocalizations.of(context)!.chooseBranchHint,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ];
                  })(),
                ],
              ),
            );
          }

          return Center(child: Text(AppLocalizations.of(context)!.loadingPhotoPermissions));
        },
      ),
    );
  }

  Widget _buildNoPermissionsState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_rounded,
            size: 80,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.noPhotoPermissions,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              AppLocalizations.of(context)!.askSupervisorForPermission,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// TAS-302: one captured photo and its stamped copy.
class _StampedShot {
  final File original;
  final DateTime capturedAt;
  final File stamped;
  final String branchName;
  const _StampedShot(this.original, this.capturedAt, this.stamped, this.branchName);
}
