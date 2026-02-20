import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import '../../data/models/branch_model.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:screenshot/screenshot.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:gal/gal.dart';

class BranchDetailsScreen extends StatefulWidget {
  final BranchModel branch;

  const BranchDetailsScreen({super.key, required this.branch});

  @override
  State<BranchDetailsScreen> createState() => _BranchDetailsScreenState();
}

class _BranchDetailsScreenState extends State<BranchDetailsScreen> {
  late BranchModel _branch;
  bool _isLoading = false;
  final ScreenshotController _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _branch = widget.branch;
  }

  Future<void> _editName() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _branch.branchName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.editName),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: l10n.pleaseEnterBranchName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(l10n.saveChanges),
            ),
          ],
        );
      },
    );

    if (newName != null &&
        newName.isNotEmpty &&
        newName != _branch.branchName) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(_branch.id)
            .update({'branchName': newName});

        setState(() {
          _branch = BranchModel(
            id: _branch.id,
            branchName: newName,
            latitude: _branch.latitude,
            longitude: _branch.longitude,
            geofenceRadius: _branch.geofenceRadius,
          );
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.errorGeneral)));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteBranch() async {
    final l10n = AppLocalizations.of(context)!;

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
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                l10n.deleteBranch,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(_branch.id)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.branchDeletedSuccessfully)),
          );
          context.pop(); // Go back to the list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.errorGeneral)));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _downloadQR() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);

    try {
      final image = await _screenshotController.capture();
      if (image == null) return;

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      await Gal.putImageBytes(image, name: '${_branch.branchName}_QR');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.qrSavedToGallery)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorGeneral)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // We encode the attendance type and branch name to match the existing requirements
    final qrData = jsonEncode({
      "type": "attendance",
      "branch": _branch.branchName,
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.branchDetails)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Screenshot(
                    controller: _screenshotController,
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset('assets/images/logo.png', height: 40),
                              const SizedBox(width: 12),
                              const Text(
                                'تسهيل',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _branch.branchName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 32),
                          QrImageView(
                            data: qrData,
                            version: QrVersions.auto,
                            size: 250.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Scan to Check-In',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _downloadQR,
                    icon: const Icon(Icons.download),
                    label: Text(
                      l10n.downloadQR,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _editName,
                          icon: const Icon(Icons.edit),
                          label: Text(l10n.editName),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _deleteBranch,
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: Text(
                            l10n.deleteBranch,
                            style: const TextStyle(color: Colors.red),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
