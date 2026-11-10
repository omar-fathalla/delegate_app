
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_profile_edit_repository.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/presentation/widgets/update_national_id_request_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Supervisor screen to edit a delegate's name, phone, personal photo, and
/// ID-card images. The national ID number is requested separately for approval.
class EditDelegateProfileScreen extends StatefulWidget {
  final Delegate supervisor;
  final Delegate? delegate;
  final DelegateSubscriptionRequest? request;

  const EditDelegateProfileScreen({
    super.key,
    required this.supervisor,
    this.delegate,
    this.request,
  }) : assert(delegate != null || request != null);

  @override
  State<EditDelegateProfileScreen> createState() =>
      _EditDelegateProfileScreenState();
}

class _EditDelegateProfileScreenState extends State<EditDelegateProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  XFile? _personalPhoto;
  Uint8List? _personalPhotoBytes;
  XFile? _idFront;
  Uint8List? _idFrontBytes;
  XFile? _idBack;
  Uint8List? _idBackBytes;
  bool _saving = false;

  String get _fullName =>
      widget.delegate?.fullName ?? widget.request?.fullName ?? '';
  String get _phone =>
      widget.delegate?.phoneNumber ?? widget.request?.phoneNumber ?? '';
  String get _nationalId =>
      widget.delegate?.nationalityID ?? widget.request?.nationalId ?? '';
  String get _companyUID => widget.delegate?.companyUID ??
      widget.request?.companyUID ??
      widget.supervisor.companyUID;
  String get _delegateUid =>
      widget.delegate?.uid ?? widget.request?.existingDelegateUid ?? '';
  String? get _requestId => widget.request?.id;
  String get _photoUrl =>
      widget.delegate?.personalPhotoUrl ?? widget.request?.profileImageUrl ?? '';
  String get _frontUrl {
    if ((widget.request?.nationalIdFrontUrl ?? '').isNotEmpty) {
      return widget.request!.nationalIdFrontUrl;
    }
    final docs = widget.delegate?.documents ?? const [];
    for (final d in docs) {
      if (d.documentKey == DocumentKey.nationalityId && d.documentURL.isNotEmpty) {
        return d.documentURL;
      }
    }
    return '';
  }
  String get _backUrl {
    if ((widget.request?.nationalIdBackUrl ?? '').isNotEmpty) {
      return widget.request!.nationalIdBackUrl;
    }
    final docs = widget.delegate?.documents ?? const [];
    for (final d in docs) {
      if (d.documentKey == DocumentKey.nationalityId &&
          (d.secondaryURL ?? '').isNotEmpty) {
        return d.secondaryURL!;
      }
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _fullName);
    _phoneController = TextEditingController(text: _phone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  InputDecoration _decoration({required String label, String? helper}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      helperText: helper,
      labelStyle: const TextStyle(fontSize: 13),
      helperStyle: TextStyle(fontSize: 11, color: colorScheme.outline),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    );
  }

  Future<void> _pick({
    required void Function(XFile file, Uint8List bytes) assign,
  }) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => assign(picked, bytes));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final nameChanged = name.isNotEmpty && name != _fullName.trim();
    final phoneChanged = phone.isNotEmpty && phone != _phone.trim();
    if (!nameChanged &&
        !phoneChanged &&
        _personalPhoto == null &&
        _idFront == null &&
        _idBack == null) {
      AppSnackBar.showError(context, 'لم يتم تغيير أي بيان.');
      return;
    }

    setState(() => _saving = true);
    final repo = DelegateProfileEditRepository();
    try {
      final result = await repo.saveProfile(
        companyUID: _companyUID,
        delegateUid: _delegateUid.isNotEmpty ? _delegateUid : null,
        requestId: _requestId,
        fullName: nameChanged ? name : null,
        phoneNumber: phoneChanged ? phone : null,
        personalPhoto: _personalPhoto,
        idFront: _idFront,
        idBack: _idBack,
      );
      if (!mounted) return;
      if (result.imagesFailed) {
        AppSnackBar.showError(
          context,
          result.message ?? 'تعذر رفع الصور. حاول مرة أخرى.',
        );
        return;
      }
      AppSnackBar.showSuccess(
        context,
        result.message ?? 'تم حفظ تعديلات المندوب في كل السلاسل.',
      );
      Navigator.of(context).pop(true);
    } on DelegateProfileEditException catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.showError(context, 'تعذر حفظ التعديلات. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openNationalIdSheet() async {
    final result = await UpdateNationalIdRequestSheet.show(
      context,
      supervisor: widget.supervisor,
      currentNationalId: _nationalId,
      companyUID: _companyUID,
      delegateUid: _delegateUid.isNotEmpty ? _delegateUid : null,
      requestId: _requestId,
      delegateName: _fullName,
    );
    if (result == true && mounted) {
      AppSnackBar.showSuccess(
        context,
        'تم إرسال طلب تعديل الرقم القومي للإدارة العليا.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل بيانات المندوب'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                _fullName.isNotEmpty ? _fullName : 'مندوب',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(fontSize: 14),
                textInputAction: TextInputAction.next,
                decoration: _decoration(label: 'الاسم الكامل'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                style: const TextStyle(fontSize: 14),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _decoration(
                  label: 'رقم الموبايل',
                  helper: 'سيتم رفض الرقم إن كان مسجلاً لمندوب آخر',
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'رقم الموبايل مطلوب';
                  if (t.length < 10) return 'رقم الموبايل غير مكتمل';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _ImageRow(
                title: 'الصورة الشخصية',
                subtitle: 'اختيار صورة جديدة يستبدل الصورة الحالية مباشرة',
                icon: Icons.person_rounded,
                bytes: _personalPhotoBytes,
                existingUrl: _photoUrl,
                onPick: () => _pick(assign: (f, b) {
                  _personalPhoto = f;
                  _personalPhotoBytes = b;
                }),
                onRemove: () => setState(() {
                  _personalPhoto = null;
                  _personalPhotoBytes = null;
                }),
              ),
              const SizedBox(height: 12),
              _ImageRow(
                title: 'صورة البطاقة الأمامية',
                subtitle: 'وجه بطاقة الرقم القومي',
                icon: Icons.badge_outlined,
                bytes: _idFrontBytes,
                existingUrl: _frontUrl,
                onPick: () => _pick(assign: (f, b) {
                  _idFront = f;
                  _idFrontBytes = b;
                }),
                onRemove: () => setState(() {
                  _idFront = null;
                  _idFrontBytes = null;
                }),
              ),
              const SizedBox(height: 12),
              _ImageRow(
                title: 'صورة البطاقة الخلفية',
                subtitle: 'ظهر بطاقة الرقم القومي',
                icon: Icons.flip_rounded,
                bytes: _idBackBytes,
                existingUrl: _backUrl,
                onPick: () => _pick(assign: (f, b) {
                  _idBack = f;
                  _idBackBytes = b;
                }),
                onRemove: () => setState(() {
                  _idBack = null;
                  _idBackBytes = null;
                }),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الرقم القومي',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _nationalId.isEmpty ? 'غير متوفر' : _nationalId,
                        style: const TextStyle(fontSize: 16, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'لا يمكن تعديل الرقم القومي مباشرة. أرسل طلباً للإدارة العليا أو الدعم الفني للاعتماد.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _openNationalIdSheet,
                        icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                        label: const Text('طلب تعديل الرقم القومي'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'جاري الحفظ...' : 'حفظ التعديلات'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    minimumSize: const Size(0, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Uint8List? bytes;
  final String existingUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ImageRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bytes,
    required this.existingUrl,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget preview;
    if (bytes != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(bytes!, width: 54, height: 54, fit: BoxFit.cover),
      );
    } else if (existingUrl.isNotEmpty) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 54,
          height: 54,
          child: AppPhotoImage(photoUrl: existingUrl, fit: BoxFit.cover),
        ),
      );
    } else {
      preview = Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 28, color: colorScheme.outline),
      );
    }

    return Row(
      children: [
        preview,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: colorScheme.outline)),
            ],
          ),
        ),
        if (bytes != null)
          IconButton(
            icon: Icon(Icons.close_rounded, color: colorScheme.error, size: 20),
            onPressed: onRemove,
            tooltip: 'حذف',
          )
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onPick,
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
            label: const Text('اختيار', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
