import 'package:delegate_app/core/l10n/display_names.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:intl/intl.dart' hide Bidi, TextDirection;
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'dart:io';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
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
  State<DelegateCameraCaptureScreen> createState() =>
      _DelegateCameraCaptureScreenState();
}

class _DelegateCameraCaptureScreenState
    extends State<DelegateCameraCaptureScreen> {
  List<PhotoPermission>? _cachedPermissions;
  PhotoPermission? _selectedPermission;
  String? _selectedBranchId;

  /// TAS-302: each shot keeps the camera original, its capture time and the
  /// stamped copy (branch + date burned in). Only stamped copies are uploaded.
  final List<_StampedShot> _shots = [];
  List<File> get _capturedPhotos => [for (final s in _shots) s.stamped];
  bool _isStamping = false;
  int _selectedPhotoIndex = 0;
  final TextEditingController _commentController = TextEditingController();
  Map<String, String>? _orgBranchesMap;

  /// TAS-387 (user review 27 Nov 2026): the chain is picked first, then a
  /// branch of that chain. Each entry is this person's membership in one
  /// chain (its own company and delegate id there).
  late final List<Delegate> _chains = _loadChains();
  late Delegate _chain = _chains.firstWhere(
    (d) => d.organizationUID == widget.delegate.organizationUID,
    orElse: () => _chains.first,
  );

  List<Delegate> _loadChains() {
    final out = <Delegate>[widget.delegate];
    try {
      if (di.sl.isRegistered<AuthLocalDataSource>()) {
        final me = widget.delegate;
        for (final d
            in di.sl<AuthLocalDataSource>().getCachedAllDelegatesData()) {
          final same =
              d.uid == me.uid ||
              (me.nationalityID.isNotEmpty &&
                  d.nationalityID == me.nationalityID);
          if (!same || d.organizationUID.isEmpty) continue;
          if (out.any((c) => c.organizationUID == d.organizationUID)) continue;
          out.add(d);
        }
      }
    } catch (_) {}
    return out;
  }

  void _selectChain(Delegate chain) {
    if (chain.organizationUID == _chain.organizationUID) return;
    setState(() {
      _chain = chain;
      _cachedPermissions = null;
      _selectedPermission = null;
      _selectedBranchId = null;
      _orgBranchesMap = null;
    });
    _loadOrganizationBranches();
    _loadOngoingPermissions();
  }

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
      final orgUID = _chain.organizationUID.trim();
      final orgName = _chain.organizationName.trim().toLowerCase();

      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .get();
      final map = <String, String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final bOrgUID = (data['organizationUID'] as String?)?.trim() ?? '';
        final bOrgName =
            ((data['organizationName'] as String?) ??
                    (data['orgName'] as String?))
                ?.trim()
                .toLowerCase() ??
            '';

        final matchUID = orgUID.isNotEmpty && bOrgUID == orgUID;
        // An empty chain name on a branch used to match every chain
        // ('x'.contains('') is true), so other chains' branches showed up.
        final matchName =
            orgName.isNotEmpty &&
            bOrgName.isNotEmpty &&
            (bOrgName == orgName ||
                bOrgName.contains(orgName) ||
                orgName.contains(bOrgName));

        if (matchUID || matchName) {
          final branchName =
              (data['branchName'] as String?) ??
              (data['name'] as String?) ??
              (data['title'] as String?) ??
              doc.id;
          map[doc.id] = branchName;
        }
      }

      if (mounted && orgUID == _chain.organizationUID.trim()) {
        setState(() {
          _orgBranchesMap = map;
        });
      }
    } catch (_) {}
  }

  void _loadOngoingPermissions() {
    context.read<PhotoPermissionBloc>().add(
      LoadOngoingPermissionsRequested(organizationUID: _chain.organizationUID),
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
    final display = BranchDisplayCache.instance.displayName(
      branchName,
      fallback: branchName,
    );
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
        _selectedPhotoIndex = _capturedPhotos.isEmpty
            ? 0
            : _capturedPhotos.length - 1;
      }
    });
    showTashilSnackBar(
      context,
      AppLocalizations.of(context)!.photoRemovedFromSession,
    );
  }

  void _showErrorSnackBar(String message) {
    // TAS-354 (C-30): kit snackbar, text only.
    showTashilSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSupervisor = widget.delegate.role == UserRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSupervisor ? l10n.offerPhotosSupervisor : l10n.offerPhotosTitle,
        ),
      ),
      body: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        listener: (context, state) {
          if (state is PhotoBatchUploadSuccess || state is PhotoUploadSuccess) {
            final offline = state is PhotoBatchUploadSuccess
                ? state.isOffline
                : (state as PhotoUploadSuccess).isOffline;
            showTashilSnackBar(
              context,
              state is PhotoBatchUploadSuccess
                  ? (offline
                        ? l10n.photosSavedOffline(state.uploadedCount)
                        : l10n.photosUploaded(state.uploadedCount))
                  : (offline ? l10n.photoSavedOffline : l10n.photoUploaded),
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
          final permissions = _cachedPermissions;
          if (permissions == null) {
            // Known layout: skeletons of the two steps (P-08).
            return ListView(
              key: const Key('capture_skeleton'),
              padding: const EdgeInsets.all(TashilSpacing.page),
              children: const [
                SummaryCardSkeleton(facts: 2),
                SizedBox(height: TashilSpacing.lg),
                Skeleton(height: 200, radius: TashilRadius.large),
              ],
            );
          }

          // Permissions of this person's company in the selected chain.
          final mine = permissions.where((p) {
            final byUid =
                _chain.companyUID.isNotEmpty &&
                p.companyUID == _chain.companyUID;
            final byName =
                p.companyName.trim().toLowerCase() ==
                _chain.companyName.trim().toLowerCase();
            return byUid || byName;
          }).toList();
          final available = mine.isNotEmpty
              ? mine
              : (widget.initialPermission != null &&
                        widget.initialPermission!.organizationUID ==
                            _chain.organizationUID
                    ? [widget.initialPermission!]
                    : <PhotoPermission>[]);

          return ListView(
            key: const Key('capture_page'),
            padding: const EdgeInsetsDirectional.fromSTEB(
              TashilSpacing.page,
              TashilSpacing.sm,
              TashilSpacing.page,
              TashilSpacing.xxl,
            ),
            children: [
              const SyncStatusBanner(),
              _stepTitle(1, l10n.captureStepPlace),
              _buildPlaceCard(context, available),
              const SizedBox(height: TashilSpacing.xl),
              _stepTitle(2, l10n.captureStepPhotos),
              ..._buildPhotosStep(context, state, available),
            ],
          );
        },
      ),
    );
  }

  /// «1 · المكان», «2 · الصور»: numbered steps (same title style as home).
  Widget _stepTitle(int n, String title) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: TashilSpacing.xs,
        bottom: TashilSpacing.sm,
        top: TashilSpacing.sm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: cs.primary,
            child: Text(
              Bidi.ltr('$n'),
              style: tt.labelMedium?.copyWith(color: cs.onPrimary),
            ),
          ),
          const SizedBox(width: TashilSpacing.sm),
          Text(title, style: tt.titleSmall),
        ],
      ),
    );
  }

  PhotoPermission? _activePermission(List<PhotoPermission> available) {
    if (available.isEmpty) return null;
    final sel = _selectedPermission;
    if (sel != null && available.any((p) => p.uid == sel.uid)) {
      return available.firstWhere((p) => p.uid == sel.uid);
    }
    return available.first;
  }

  /// The permission's branches in the selected chain, sorted by name.
  List<MapEntry<String, String>> _branchesOf(PhotoPermission perm) {
    final unique = <String, String>{};
    for (var i = 0; i < perm.branchIds.length; i++) {
      final id = perm.branchIds[i].trim();
      if (id.isEmpty) continue;
      final name =
          i < perm.branchNames.length && perm.branchNames[i].trim().isNotEmpty
          ? perm.branchNames[i].trim()
          : AppLocalizations.of(context)!.branchWithId(id);
      final map = _orgBranchesMap;
      if (map != null && map.isNotEmpty) {
        final inChain =
            map.containsKey(id) ||
            map.values.any((n) => n.trim().toLowerCase() == name.toLowerCase());
        if (!inChain) continue;
      }
      unique.putIfAbsent(id, () => _orgBranchesMap?[id] ?? name);
    }
    if (unique.isEmpty && (_orgBranchesMap?.isNotEmpty ?? false)) {
      unique.addAll(_orgBranchesMap!);
    }
    return unique.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  }

  /// The selected branch, or the only one when there is just one.
  MapEntry<String, String>? _effectiveBranch(PhotoPermission? perm) {
    if (perm == null) return null;
    final branches = _branchesOf(perm);
    final sel = _selectedBranchId;
    if (sel != null) {
      for (final b in branches) {
        if (b.key == sel) return b;
      }
    }
    return branches.length == 1 ? branches.first : null;
  }

  /// Step 1: chain, then branch (C-10 DropdownMenus), the permission when
  /// there are several, and its facts as icon + text.
  Widget _buildPlaceCard(
    BuildContext context,
    List<PhotoPermission> available,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final perm = _activePermission(available);
    final branches = perm == null
        ? const <MapEntry<String, String>>[]
        : _branchesOf(perm);
    final branch = _effectiveBranch(perm);

    Widget fact(IconData icon, String text) => Padding(
      padding: const EdgeInsetsDirectional.only(top: TashilSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: TashilSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );

    return Card.filled(
      key: const Key('capture_place_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownMenu<String>(
              key: const Key('photo_chain_menu'),
              initialSelection: _chain.organizationUID,
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: false,
              enabled: _chains.length > 1,
              label: Text(l10n.attChainLabel),
              leadingIcon: const Icon(Symbols.hub_rounded),
              dropdownMenuEntries: [
                for (final c in _chains)
                  DropdownMenuEntry<String>(
                    value: c.organizationUID,
                    label: localizeChainName(c.organizationName, l10n),
                  ),
              ],
              onSelected: (v) {
                if (v == null) return;
                _selectChain(_chains.firstWhere((c) => c.organizationUID == v));
              },
            ),
            const SizedBox(height: TashilSpacing.md),
            if (perm == null)
              EmptyState(
                key: const Key('capture_no_permission'),
                icon: Symbols.lock_rounded,
                title: l10n.noPhotoPermissions,
                message: l10n.askSupervisorForPermission,
              )
            else ...[
              if (available.length > 1) ...[
                DropdownMenu<String>(
                  key: const Key('photo_permission_menu'),
                  initialSelection: perm.uid,
                  expandedInsets: EdgeInsets.zero,
                  requestFocusOnTap: false,
                  label: Text(l10n.choosePhotoPermission),
                  leadingIcon: const Icon(Symbols.assignment_turned_in_rounded),
                  dropdownMenuEntries: [
                    for (final p in available)
                      DropdownMenuEntry<String>(
                        value: p.uid,
                        label: l10n.permissionOption(
                          p.companyName,
                          (p.department ?? '').trim().isNotEmpty
                              ? ' (${p.department})'
                              : '',
                          p.branchNames.length,
                        ),
                      ),
                  ],
                  onSelected: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedPermission = available.firstWhere(
                        (p) => p.uid == v,
                      );
                      _selectedBranchId = null;
                    });
                  },
                ),
                const SizedBox(height: TashilSpacing.md),
              ],
              if (branches.isEmpty)
                Builder(
                  builder: (context) {
                    final sem = Theme.of(
                      context,
                    ).extension<TashilSemanticColors>();
                    return MaterialBanner(
                      key: const Key('capture_no_branches'),
                      backgroundColor:
                          sem?.warningContainer ?? cs.tertiaryContainer,
                      leading: Icon(
                        Symbols.warning_rounded,
                        color:
                            sem?.onWarningContainer ?? cs.onTertiaryContainer,
                      ),
                      content: Text(
                        l10n.noBranchesInPermissionFor(_chain.organizationName),
                        style: tt.bodyMedium?.copyWith(
                          color:
                              sem?.onWarningContainer ?? cs.onTertiaryContainer,
                        ),
                      ),
                      actions: const [SizedBox.shrink()],
                    );
                  },
                )
              else
                DropdownMenu<String>(
                  key: ValueKey(
                    'branch_dropdown_${_chain.organizationUID}_${perm.uid}',
                  ),
                  initialSelection: branch?.key,
                  expandedInsets: EdgeInsets.zero,
                  requestFocusOnTap: false,
                  enableFilter: branches.length > 6,
                  label: Text(l10n.attBranchLabel),
                  leadingIcon: const Icon(Symbols.storefront_rounded),
                  dropdownMenuEntries: [
                    for (final b in branches)
                      DropdownMenuEntry<String>(
                        value: b.key,
                        label: BranchDisplayCache.instance.displayName(b.value),
                      ),
                  ],
                  onSelected: (v) {
                    if (v == null) return;
                    final name = branches.firstWhere((b) => b.key == v).value;
                    setState(() => _selectedBranchId = v);
                    _restampForBranch(name);
                  },
                ),
              const SizedBox(height: TashilSpacing.sm),
              fact(
                Symbols.verified_rounded,
                l10n.offerPhotoPermissionOf(perm.companyName),
              ),
              if ((perm.department ?? '').trim().isNotEmpty)
                fact(
                  Symbols.groups_rounded,
                  l10n.departmentLabel(perm.department!),
                ),
              fact(
                Symbols.event_available_rounded,
                l10n.capturePermissionUntil(
                  DateFormat('d MMMM', locale).format(perm.endDate),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Step 2: the photos as a grid (same as the photo report), the add tile,
  /// the visit notes and the send button; upload progress is a determinate
  /// linear indicator (the count is known).
  List<Widget> _buildPhotosStep(
    BuildContext context,
    PhotoPermissionState state,
    List<PhotoPermission> available,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final perm = _activePermission(available);
    final branch = _effectiveBranch(perm);

    if (perm == null || branch == null) {
      return [
        Card.outlined(
          key: const Key('capture_choose_branch_first'),
          margin: EdgeInsets.zero,
          child: EmptyState(
            icon: Symbols.storefront_rounded,
            title: l10n.chooseBranchToStart,
            message: l10n.chooseBranchHint,
          ),
        ),
      ];
    }

    final branchName = branch.value;
    Widget addTile({bool big = false}) => Card.outlined(
      key: Key(big ? 'capture_first_photo' : 'capture_add_photo'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isStamping
            ? null
            : () => _capturePhoto(isAddingMore: true, branchName: branchName),
        child: Padding(
          padding: EdgeInsets.all(big ? TashilSpacing.xl : TashilSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(TashilSpacing.md),
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.add_a_photo_rounded,
                  color: cs.onPrimary,
                  size: big ? 32 : 20,
                ),
              ),
              const SizedBox(height: TashilSpacing.sm),
              Text(
                big ? l10n.takeFirstPhoto : l10n.addPhoto,
                style: (big ? tt.titleSmall : tt.labelMedium),
                textAlign: TextAlign.center,
              ),
              if (big) ...[
                const SizedBox(height: TashilSpacing.xs),
                Text(
                  l10n.multiPhotoHint,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (_shots.isEmpty) {
      return [
        if (_isStamping)
          const Skeleton(height: 180, radius: TashilRadius.large)
        else
          addTile(big: true),
      ];
    }

    final uploading = state is PhotoBatchUploadInProgress ? state : null;
    final singleUploading = state is PhotoPermissionUploadInProgress;

    return [
      GridView.count(
        key: const Key('capture_grid'),
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: TashilSpacing.sm,
        crossAxisSpacing: TashilSpacing.sm,
        children: [
          for (var i = 0; i < _shots.length; i++)
            ClipRRect(
              key: ValueKey('capture_shot_$i'),
              borderRadius: BorderRadius.circular(TashilRadius.medium),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Material(
                    color: cs.surfaceContainerHighest,
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedPhotoIndex = i);
                        _openFullScreen(branchName);
                      },
                      child: Ink.image(
                        image: FileImage(_shots[i].stamped),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: TashilSpacing.xs,
                    end: TashilSpacing.xs,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: cs.primary,
                      child: Text(
                        Bidi.ltr('${i + 1}'),
                        style: tt.labelSmall?.copyWith(color: cs.onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_isStamping)
            const Skeleton(radius: TashilRadius.medium, height: double.infinity)
          else
            addTile(),
        ],
      ),
      const SizedBox(height: TashilSpacing.xs),
      Text(
        l10n.captureTapToReview,
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: TashilSpacing.lg),
      TextField(
        key: const Key('capture_notes'),
        controller: _commentController,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: l10n.visitNotesLabel(_shots.length),
          hintText: l10n.visitNotesHint,
        ),
      ),
      const SizedBox(height: TashilSpacing.xl),
      if (uploading != null) ...[
        Text(
          l10n.uploadingPhotoXofY(uploading.current, uploading.total),
          style: tt.titleSmall,
        ),
        const SizedBox(height: TashilSpacing.sm),
        LinearProgressIndicator(
          key: const Key('capture_upload_progress'),
          value: uploading.total > 0
              ? uploading.current / uploading.total
              : null,
        ),
      ] else if (singleUploading) ...[
        Text(l10n.uploadingPhotosReport, style: tt.titleSmall),
        const SizedBox(height: TashilSpacing.sm),
        const LinearProgressIndicator(key: Key('capture_upload_progress')),
      ] else
        FilledButton.icon(
          key: const Key('photo_submit_button'),
          onPressed: _isStamping ? null : () => _submit(context, perm, branch),
          icon: const Icon(Symbols.cloud_upload_rounded),
          label: Text(l10n.submitReportCount(_shots.length)),
        ),
    ];
  }

  Future<void> _submit(
    BuildContext context,
    PhotoPermission perm,
    MapEntry<String, String> branch,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (_capturedPhotos.isEmpty) {
      _showErrorSnackBar(l10n.takeAtLeastOnePhoto);
      return;
    }
    // TAS-302: every uploaded photo must carry the branch it is sent for.
    await _restampForBranch(branch.value);
    if (!context.mounted || _capturedPhotos.isEmpty) return;
    final uploaderName = widget.delegate.role == UserRole.admin
        ? l10n.nameCompanySupervisor(_chain.fullName)
        : _chain.fullName;
    context.read<PhotoPermissionBloc>().add(
      UploadBatchPhotosRequested(
        organizationUID: perm.organizationUID.isNotEmpty
            ? perm.organizationUID
            : _chain.organizationUID,
        companyUID: perm.companyUID.isNotEmpty
            ? perm.companyUID
            : _chain.companyUID,
        companyName: perm.companyName.isNotEmpty
            ? perm.companyName
            : _chain.companyName,
        companyCode: perm.companyCode,
        permissionId: perm.uid,
        branchId: branch.key,
        branchName: branch.value,
        delegateUID: _chain.uid,
        delegateName: uploaderName,
        imageFiles: List<File>.from(_capturedPhotos),
        comment: _commentController.text,
        latitude: 0.0,
        longitude: 0.0,
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
  const _StampedShot(
    this.original,
    this.capturedAt,
    this.stamped,
    this.branchName,
  );
}
