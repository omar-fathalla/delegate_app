import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../widgets/sync_status_banner.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';

class DelegateCameraCaptureScreen extends StatefulWidget {
  final Delegate delegate;

  const DelegateCameraCaptureScreen({super.key, required this.delegate});

  @override
  State<DelegateCameraCaptureScreen> createState() => _DelegateCameraCaptureScreenState();
}

class _DelegateCameraCaptureScreenState extends State<DelegateCameraCaptureScreen> {
  List<PhotoPermission>? _cachedPermissions;
  PhotoPermission? _selectedPermission;
  String? _selectedBranchId;
  String? _selectedBranchName;
  File? _imageFile;
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOngoingPermissions();
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

  Future<void> _captureImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      // إجبار المندوب على الكاميرا فقط لمنع التلاعب
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50, // ضغط الصورة بشكل أكبر
        maxWidth: 1080, // تحديد أقصى عرض
        maxHeight: 1080, // تحديد أقصى طول
      );

      if (photo != null) {
        setState(() {
          _imageFile = File(photo.path);
        });
      }
    } catch (e) {
      _showErrorSnackBar('فشل في فتح الكاميرا: $e');
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تصوير العروض الميدانية',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        listener: (context, state) {
          if (state is PhotoUploadSuccess) {
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
                            ? '⏳ تم حفظ الصورة محلياً بأمان، وسيتم رفعها تلقائياً للسيرفر فور توفر الإنترنت.'
                            : '✅ تم رفع الصورة وحفظ التقرير بنجاح على السيرفر.',
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
              _imageFile = null;
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
            return const Center(
              child: AppLoadingIndicator(
                style: AppLoadingStyle.threeArchedCircle,
                label: 'جاري جلب معلومات أذونات التصوير...',
              ),
            );
          }

          final permissionsToUse = _cachedPermissions ??
              (state is OngoingPermissionsLoaded ? state.permissions : null);

          if (permissionsToUse != null) {
            // تصفية الأذونات لتظهر فقط الأذونات الممنوحة لشركة المندوب (بالـ UID، الكود، أو اسم الشركة)
            final delegatePermissions = permissionsToUse.where((p) {
              final matchUID = widget.delegate.companyUID.isNotEmpty && p.companyUID == widget.delegate.companyUID;
              final matchName = p.companyName.trim().toLowerCase() == widget.delegate.companyName.trim().toLowerCase();
              return matchUID || matchName;
            }).toList();

            if (delegatePermissions.isEmpty) {
              return _buildNoPermissionsState(theme);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SyncStatusBanner(),
                  // Auto-selected permission/campaign info
                  ...(() {
                    if (_selectedPermission == null && delegatePermissions.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _selectedPermission = delegatePermissions.first;
                          });
                        }
                      });
                    }
                    final activePermission = _selectedPermission ?? delegatePermissions.first;

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
                                    'إذن تصوير العروض: ${activePermission.companyName}',
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
                              'الشركة: ${activePermission.companyName}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
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

                      // Branch selector dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedBranchId,
                        decoration: InputDecoration(
                          labelText: 'اختر الفرع *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.store_rounded),
                        ),
                        items: List.generate(activePermission.branchIds.length, (index) {
                          final id = activePermission.branchIds[index];
                          final name = activePermission.branchNames[index];
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(name),
                          );
                        }),
                        onChanged: (value) {
                          if (value == null) return;
                          final index = activePermission.branchIds.indexOf(value);
                          setState(() {
                            _selectedBranchId = value;
                            _selectedBranchName = index != -1
                                ? activePermission.branchNames[index]
                                : value;
                          });
                        },
                      ),
                    ];
                  })(),

                  const SizedBox(height: 20),

                  // Camera capture preview area
                  if (_selectedBranchId != null) ...[
                    if (_imageFile == null)
                      InkWell(
                        onTap: _captureImage,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 220,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                              width: 1.5,
                              strokeAlign: BorderSide.strokeAlignInside,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_rounded,
                                size: 54,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'التقط صورة العرض الميداني بالكاميرا',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'يتم التقاط الصورة بالكاميرا المباشرة فقط',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // Photo preview
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 240,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Image.file(
                            _imageFile!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _captureImage,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة التقاط الصورة'),
                      ),
                      const SizedBox(height: 20),

                      // Comment input
                      TextField(
                        controller: _commentController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'أضف تعليقاً على الصورة (اختياري)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          hintText: 'مثال: تم عرض المنتجات وتنسيق الرف بشكل كامل...',
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit button
                      state is PhotoPermissionUploadInProgress
                          ? Container(
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
                                    'جاري رفع الصورة إلى السيرفر وحفظ التقرير...',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ElevatedButton(
                              onPressed: () {
                                final currentPerm = _selectedPermission ?? delegatePermissions.first;
                                final orgUID = currentPerm.organizationUID.isNotEmpty
                                    ? currentPerm.organizationUID
                                    : widget.delegate.organizationUID;
                                final compUID = currentPerm.companyUID.isNotEmpty
                                    ? currentPerm.companyUID
                                    : widget.delegate.companyUID;

                                context.read<PhotoPermissionBloc>().add(
                                      UploadPhotoRequested(
                                        organizationUID: orgUID,
                                        companyUID: compUID,
                                        permissionId: currentPerm.uid,
                                        branchId: _selectedBranchId!,
                                        branchName: _selectedBranchName!,
                                        delegateUID: widget.delegate.uid,
                                        delegateName: widget.delegate.fullName,
                                        imageFile: _imageFile!,
                                        comment: _commentController.text,
                                        latitude: 0.0,
                                        longitude: 0.0,
                                      ),
                                    );
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'تسجيل التقرير الميداني',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                    ],
                  ],
                ],
              ),
            );
          }

          return const Center(child: Text('جاري جلب معلومات أذونات التصوير...'));
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
            'لا توجد أذونات تصوير نشطة لشركتك',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'يرجى التواصل مع مشرف الشركة لتقديم طلب إذن تصوير، والتأكد من اعتماده من إدارة التسويق.',
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
