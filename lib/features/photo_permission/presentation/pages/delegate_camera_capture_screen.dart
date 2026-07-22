import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';

class DelegateCameraCaptureScreen extends StatefulWidget {
  final Delegate delegate;

  const DelegateCameraCaptureScreen({super.key, required this.delegate});

  @override
  State<DelegateCameraCaptureScreen> createState() => _DelegateCameraCaptureScreenState();
}

class _DelegateCameraCaptureScreenState extends State<DelegateCameraCaptureScreen> {
  PhotoPermission? _selectedPermission;
  String? _selectedBranchId;
  String? _selectedBranchName;
  File? _imageFile;
  final TextEditingController _commentController = TextEditingController();
  bool _gettingLocation = false;
  double? _latitude;
  double? _longitude;

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
        imageQuality: 70, // ضغط الصورة لتقليل الاستهلاك
      );

      if (photo != null) {
        setState(() {
          _imageFile = File(photo.path);
        });
        _getCurrentLocation();
      }
    } catch (e) {
      _showErrorSnackBar('فشل في فتح الكاميرا: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _gettingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showErrorSnackBar('خدمات الموقع الجغرافي معطلة. يرجى تفعيل الـ GPS.');
        setState(() => _gettingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorSnackBar('تم رفض صلاحية الوصول للموقع الجغرافي.');
          setState(() => _gettingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showErrorSnackBar('صلاحيات الموقع مرفوضة دائماً. يرجى تفعيلها من إعدادات الهاتف.');
        setState(() => _gettingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _gettingLocation = false;
      });
    } catch (e) {
      _showErrorSnackBar('فشل في جلب الموقع الجغرافي: $e');
      setState(() => _gettingLocation = false);
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ تم رفع التقرير والصورة بنجاح في النظام'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setState(() {
              _imageFile = null;
              _commentController.clear();
              _latitude = null;
              _longitude = null;
            });
            _loadOngoingPermissions();
          } else if (state is PhotoPermissionError) {
            _showErrorSnackBar(state.message);
          }
        },
        builder: (context, state) {
          if (state is PhotoPermissionLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is OngoingPermissionsLoaded) {
            // تصفية الأذونات لتظهر فقط الأذونات الممنوحة لشركة المندوب (بالـ UID، الكود، أو اسم الشركة)
            final delegatePermissions = state.permissions.where((p) {
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
                  // Step 1: Select permission/campaign
                  Text(
                    '1. اختر العرض أو الإذن المصرح لك به:',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<PhotoPermission>(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    hint: const Text('اختر الإذن المتاح لشركتك'),
                    initialValue: _selectedPermission,
                    items: delegatePermissions.map((permission) {
                      return DropdownMenuItem(
                        value: permission,
                        child: Text(
                          'إذن تصوير العروض - ${permission.companyName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedPermission = val;
                        _selectedBranchId = null;
                        _selectedBranchName = null;
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Step 2: Select Branch
                  if (_selectedPermission != null) ...[
                    Text(
                      '2. حدد الفرع الذي تتواجد فيه الآن:',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      hint: const Text('اختر الفرع المتواجد به'),
                      initialValue: _selectedBranchId,
                      items: List.generate(_selectedPermission!.branchIds.length, (index) {
                        final id = _selectedPermission!.branchIds[index];
                        final name = _selectedPermission!.branchNames[index];
                        return DropdownMenuItem(
                          value: id,
                          child: Text(name),
                        );
                      }),
                      onChanged: (val) {
                        setState(() {
                          _selectedBranchId = val;
                          _selectedBranchName = _selectedPermission!.branchNames[
                              _selectedPermission!.branchIds.indexOf(val!)];
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Step 3: Capture & comment
                  if (_selectedBranchId != null) ...[
                    Text(
                      '3. التقاط الصورة الميدانية:',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (_imageFile == null)
                      ElevatedButton.icon(
                        onPressed: _captureImage,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                        ),
                        icon: const Icon(Icons.camera_alt_rounded, size: 28),
                        label: const Text(
                          'فتح الكاميرا والتقاط الصورة',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      )
                    else ...[
                      // Display captured photo
                      Container(
                        height: 250,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colorScheme.outlineVariant),
                          image: DecorationImage(
                            image: FileImage(_imageFile!),
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

                      // Coordinates verification
                      Row(
                        children: [
                          Icon(
                            _latitude != null ? Icons.location_on_rounded : Icons.location_searching_rounded,
                            color: _latitude != null ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _gettingLocation
                                  ? 'جاري تحديد موقعك الجغرافي...'
                                  : (_latitude != null
                                      ? 'تم تحديد إحداثيات الموقع بدقة بنجاح.'
                                      : 'لم يتم رصد إحداثيات الموقع بعد.'),
                              style: TextStyle(
                                fontSize: 12,
                                color: _latitude != null ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                          if (_latitude == null && !_gettingLocation)
                            IconButton(
                              icon: const Icon(Icons.my_location_rounded),
                              onPressed: _getCurrentLocation,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

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
                          ? const Center(
                              child: Column(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 8),
                                  Text('جاري رفع الصورة والتقرير إلى السيرفر...'),
                                ],
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _latitude == null
                                  ? null
                                  : () {
                                      context.read<PhotoPermissionBloc>().add(
                                            UploadPhotoRequested(
                                              organizationUID: widget.delegate.organizationUID,
                                              companyUID: widget.delegate.companyUID,
                                              permissionId: _selectedPermission!.uid,
                                              branchId: _selectedBranchId!,
                                              branchName: _selectedBranchName!,
                                              delegateUID: widget.delegate.uid,
                                              delegateName: widget.delegate.fullName,
                                              imageFile: _imageFile!,
                                              comment: _commentController.text,
                                              latitude: _latitude!,
                                              longitude: _longitude!,
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
