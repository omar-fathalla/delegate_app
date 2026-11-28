import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';
import '../../data/models/branch_model.dart';
import '../bloc/branch_bloc.dart';
import 'add_branch_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:screenshot/screenshot.dart';
import 'dart:convert';
import 'package:gal/gal.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/data/services/branch_attendance_qr_service.dart';

class BranchDetailsScreen extends StatelessWidget {
  final BranchModel branch;

  /// TAS-372: the signed QR source; defaults to the `branchAttendanceQr`
  /// callable. Injectable for tests.
  final BranchAttendanceQrService? qrService;

  const BranchDetailsScreen({super.key, required this.branch, this.qrService});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<BranchBloc>(),
      child: _BranchDetailsView(
        branch: branch,
        qrService: qrService ?? FirebaseBranchAttendanceQrService(),
      ),
    );
  }
}

class _BranchDetailsView extends StatefulWidget {
  final BranchModel branch;
  final BranchAttendanceQrService qrService;

  const _BranchDetailsView({required this.branch, required this.qrService});

  @override
  State<_BranchDetailsView> createState() => _BranchDetailsViewState();
}

class _BranchDetailsViewState extends State<_BranchDetailsView> {
  late BranchModel _branch;
  bool _isDownloading = false;
  final ScreenshotController _screenshotController = ScreenshotController();

  /// TAS-372: the branch's signed QR (null until loaded, or on failure).
  BranchAttendanceQr? _signedQr;
  bool _qrBusy = false;

  @override
  void initState() {
    super.initState();
    _branch = widget.branch;
    _loadSignedQr();
  }

  Future<void> _loadSignedQr({bool regenerate = false}) async {
    final orgUid = _branch.organizationUID?.trim() ?? '';
    if (_branch.id.isEmpty || orgUid.isEmpty) return;
    setState(() => _qrBusy = true);
    try {
      final qr = await widget.qrService.fetch(
        branchId: _branch.id,
        organizationUID: orgUid,
        regenerate: regenerate,
      );
      if (!mounted) return;
      setState(() => _signedQr = qr);
      if (regenerate) {
        AppSnackBar.showSuccess(
          context,
          AppLocalizations.of(context)!.branchQrRegenerated,
        );
      }
    } catch (e) {
      debugPrint('branchAttendanceQr failed: ${e.runtimeType}');
      if (mounted && regenerate) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.branchQrLoadFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  /// Version + 1: the QR printed before stops working (TAS-372).
  Future<void> _regenerateQr() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showTashilDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.branchQrRegenerateTitle),
        content: Text(l10n.branchQrRegenerateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
          ),
          TextButton(
            key: const Key('branchQr.confirmRegenerate'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.branchQrRegenerateConfirm),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _loadSignedQr(regenerate: true);
  }

  Future<void> _editBranch() async {
    final updated = await Navigator.of(context).push<BranchModel>(
      MaterialPageRoute(
        builder: (_) => AddBranchScreen(
          showAppBar: true,
          branchToEdit: _branch,
        ),
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _branch = updated;
      });
    }
  }

  Future<void> _deleteBranch() async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.deleteBranch),
          content: Text(l10n.deleteBranchConfirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                l10n.deleteBranch,
                style: TextStyle(color: theme.colorScheme.onError),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      context.read<BranchBloc>().add(
        BranchDeleteRequested(branchId: _branch.id),
      );
    }
  }

  Future<void> _downloadQR() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isDownloading = true);

    try {
      bool hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (!hasAccess) {
        throw Exception('Storage permission denied');
      }

      final image = await _screenshotController.capture(
        pixelRatio: 4.0,
        delay: const Duration(milliseconds: 200),
      );

      if (image == null) {
        throw Exception('Failed to capture QR code image');
      }

      await Gal.putImageBytes(image, name: 'Tashil_${_branch.branchName}_QR');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.qrSavedToGallery),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.errorGeneral}: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final orgUid = _branch.organizationUID?.trim() ?? '';
    // TAS-372: the server-signed QR when the branch has one; the old
    // unsigned QR otherwise (still accepted until the first signed QR).
    final signed = _signedQr;
    final qrData = signed != null && signed.isSigned
        ? jsonEncode(signed.payload)
        : jsonEncode({
            'type': 'attendance',
            'branch': _branch.branchName,
            if (_branch.id.isNotEmpty) 'branchId': _branch.id,
            if (orgUid.isNotEmpty) 'organizationUID': orgUid,
          });

    return BlocConsumer<BranchBloc, BranchState>(
      listener: (context, state) {
        if (state is BranchUpdateSuccess) {
          setState(() {
            _branch = state.branch is BranchModel
                ? state.branch as BranchModel
                : BranchModel(
                    id: state.branch.id,
                    branchName: state.branch.branchName,
                    latitude: state.branch.latitude,
                    longitude: state.branch.longitude,
                    geofenceRadius: state.branch.geofenceRadius,
                    organizationUID: state.branch.organizationUID,
                    organizationName: state.branch.organizationName,
                  );
          });
        } else if (state is BranchDeleteSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.branchDeletedSuccessfully)),
          );
          context.pop();
        } else if (state is BranchError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) {
        final isBlocLoading = state is BranchLoading;
        final isLoading = _isDownloading || isBlocLoading;

        return Scaffold(
          appBar: AdminHeader(
            subtitle: l10n.branchDetails,
            showBackButton: true,
            onBackPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else if (GoRouter.of(context).canPop()) {
                context.pop();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Screenshot(
                      controller: _screenshotController,
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tashil',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: theme.colorScheme.primary,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _branch.branchName,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              if (_branch.organizationName != null &&
                                  _branch.organizationName!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.corporate_fare_rounded,
                                        size: 16,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _branch.organizationName!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 32),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 15,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: QrImageView(
                                  data: qrData,
                                  version: QrVersions.auto,
                                  size: 240.0,
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Colors.black,
                                  ),
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Colors.black,
                                  ),
                                  backgroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 32),
                              Text(
                                'Scan to Check-In',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: theme.colorScheme.outline,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: TashilSpacing.md),
                    // TAS-372: signed or old QR, and regenerate (version + 1).
                    Text(
                      signed != null && signed.isSigned
                          ? l10n.branchQrSigned(signed.version)
                          : l10n.branchQrLegacy,
                      key: const Key('branchQr.status'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_branch.id.isNotEmpty && orgUid.isNotEmpty)
                      TextButton.icon(
                        key: const Key('branchQr.regenerate'),
                        onPressed: isLoading || _qrBusy ? null : _regenerateQr,
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: Text(l10n.branchQrRegenerate),
                      ),
                    const SizedBox(height: TashilSpacing.lg),
                    FilledButton.icon(
                      onPressed: isLoading || _qrBusy ? null : _downloadQR,
                      icon: const Icon(Icons.file_download_rounded),
                      label: Text(
                        l10n.downloadQR,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: isLoading ? null : _editBranch,
                            icon: const Icon(Icons.edit_rounded),
                            label: Text(l10n.editBranch),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isLoading ? null : _deleteBranch,
                            icon: Icon(
                              Icons.delete_rounded,
                              color: theme.colorScheme.error,
                            ),
                            label: Text(
                              l10n.deleteBranch,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: theme.colorScheme.error.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isLoading)
                Positioned.fill(
                  child: Container(
                    color: theme.colorScheme.surface.withValues(alpha: 0.7),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
