import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/widgets/branch_name_label.dart';
import 'supervisor_permissions_screen.dart';
import '../widgets/company_name_with_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';
import '../../domain/photo_permission_query_scope.dart';
import '../../domain/entities/photo_permission_departments.dart';
import 'captured_photos_view_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MarketingPermissionsScreen extends StatefulWidget {
  final Delegate marketingDelegate;

  const MarketingPermissionsScreen({super.key, required this.marketingDelegate});

  @override
  State<MarketingPermissionsScreen> createState() => _MarketingPermissionsScreenState();
}

class _MarketingPermissionsScreenState extends State<MarketingPermissionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedPermissionIds = {};
  String _selectedStatusFilter = 'active'; // افتراضياً الأذونات النشطة فقط
  Set<String> _selectedDepartments = {}; // مجموعة الأقسام المحددة (فارغة = الكل)
  bool _isPinned = false; // هل الفلتر الحالي مثبت كافتراضي
  String _searchQuery = '';

  bool get _isPromotionUser =>
      widget.marketingDelegate.role == UserRole.marketingPromotion ||
      widget.marketingDelegate.role == UserRole.branchesMarketingManager ||
      widget.marketingDelegate.role == UserRole.superAdmin;

  bool get _isSuperAdmin => widget.marketingDelegate.role == UserRole.superAdmin;
  bool get _isTechnicalSupport =>
      widget.marketingDelegate.role == UserRole.technicalSupport;

  // Mohamed 2026-11-10: only super-admin and technical support may
  // approve or reject photo permissions.
  bool get _canApproveOrReject =>
      widget.marketingDelegate.role == UserRole.technicalSupport ||
      widget.marketingDelegate.role == UserRole.superAdmin;

  bool get _canEditDates =>
      widget.marketingDelegate.role == UserRole.marketingPromotion ||
      widget.marketingDelegate.role == UserRole.marketing ||
      widget.marketingDelegate.role == UserRole.organizationAdmin ||
      widget.marketingDelegate.role == UserRole.branchesMarketingManager ||
      widget.marketingDelegate.role == UserRole.technicalSupport ||
      widget.marketingDelegate.role == UserRole.superAdmin;

  String get _approverText {
    final approverName = widget.marketingDelegate.fullName.isNotEmpty
        ? widget.marketingDelegate.fullName
        : '${widget.marketingDelegate.firstName} ${widget.marketingDelegate.lastName}'.trim();
    if (approverName.isNotEmpty) return approverName;
    if (widget.marketingDelegate.role == UserRole.technicalSupport) {
      return 'الدعم الفني';
    }
    return widget.marketingDelegate.uid;
  }

  Future<void> _openPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone) async {
    var cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '2$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _loadPinnedDepartments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'pinned_photo_departments_${widget.marketingDelegate.uid}';
      final pinned = prefs.getStringList(key);
      if (pinned != null && pinned.isNotEmpty) {
        if (mounted) {
          setState(() {
            _selectedDepartments = pinned.toSet();
            _isPinned = true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _togglePinCurrentFilter() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pinned_photo_departments_${widget.marketingDelegate.uid}';
    if (_isPinned) {
      await prefs.remove(key);
      if (mounted) {
        setState(() {
          _isPinned = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء تثبيت الفلتر'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (_selectedDepartments.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يرجى اختيار قسم أو أكثر أولاً لتثبيته كافتراضي'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      await prefs.setStringList(key, _selectedDepartments.toList());
      if (mounted) {
        setState(() {
          _isPinned = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تثبيت (${_selectedDepartments.length}) قسم كفلتر افتراضي'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildDragHandlePill(ColorScheme colorScheme) {
    return Center(
      child: Container(
        width: 38,
        height: 4.5,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Widget _buildConnectedActionGroup({
    required ColorScheme colorScheme,
    required String cancelLabel,
    required VoidCallback onCancel,
    String? primaryLabel,
    IconData? primaryIcon,
    VoidCallback? onPrimary,
    Color? primaryColor,
  }) {
    final activePrimaryColor = primaryColor ?? colorScheme.primary;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onCancel,
              child: Center(
                child: Text(
                  cancelLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          if (primaryLabel != null) ...[
            VerticalDivider(width: 1, thickness: 1, color: colorScheme.outlineVariant),
            Expanded(
              child: InkWell(
                onTap: onPrimary,
                child: Container(
                  color: onPrimary != null
                      ? activePrimaryColor.withValues(alpha: 0.12)
                      : Colors.transparent,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (primaryIcon != null) ...[
                        Icon(
                          primaryIcon,
                          size: 18,
                          color: onPrimary != null
                              ? activePrimaryColor
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          primaryLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: onPrimary != null
                                ? activePrimaryColor
                                : colorScheme.onSurface.withValues(alpha: 0.38),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showBranchesDialog(BuildContext context, String companyName, List<String> branchNames) {
    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    Widget buildContent(BuildContext modalContext) {
      final theme = Theme.of(modalContext);
      final colorScheme = theme.colorScheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          isDesktop ? 20 : 12,
          20,
          20 + MediaQuery.viewInsetsOf(modalContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isDesktop) _buildDragHandlePill(colorScheme),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.store_rounded, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الفروع المعتمدة (${branchNames.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        companyName,
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (branchNames.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('لا توجد فروع مسجلة')),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(modalContext).height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: branchNames.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      title: BranchNameLabel(
                        branchName: branchNames[index],
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            _buildConnectedActionGroup(
              colorScheme: colorScheme,
              cancelLabel: 'إغلاق',
              onCancel: () => Navigator.pop(modalContext),
            ),
          ],
        ),
      );
    }

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: buildContent(dialogContext),
          ),
        ),
      );
    } else {
      showM3ModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) => buildContent(sheetContext),
      );
    }
  }

  void _showSupervisorDialog(BuildContext context, PhotoPermission permission) {
    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    Future<Map<String, dynamic>?> fetchSupervisorInfo() async {
      final firestore = FirebaseFirestore.instance;

      Map<String, dynamic>? extractInfo(Map<String, dynamic>? data) {
        if (data == null) return null;
        final name = (data['fullName'] ??
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}').toString().trim();
        final phone = (data['phoneNumber'] ?? data['phone'] ?? '').toString().trim();
        if (name.isNotEmpty || phone.isNotEmpty) {
          return {
            'name': name.isNotEmpty ? name : 'مشرف الشركة',
            'phone': phone,
            'companyName': data['companyName'] ?? permission.companyName,
          };
        }
        return null;
      }

      try {
        // Strategy 1: Look in users/{requestedBy}
        if (permission.requestedBy.isNotEmpty) {
          final userDoc = await firestore.collection('users').doc(permission.requestedBy).get();
          if (userDoc.exists) {
            final res = extractInfo(userDoc.data());
            if (res != null) return res;
          }
        }

        // Strategy 2: Look in organizations/{orgId}/companies/{compId}/delegates/{requestedBy}
        if (permission.organizationUID.isNotEmpty && permission.companyUID.isNotEmpty && permission.requestedBy.isNotEmpty) {
          final delegateDoc = await firestore
              .collection('organizations')
              .doc(permission.organizationUID)
              .collection('companies')
              .doc(permission.companyUID)
              .collection('delegates')
              .doc(permission.requestedBy)
              .get();
          if (delegateDoc.exists) {
            final res = extractInfo(delegateDoc.data());
            if (res != null) return res;
          }
        }

        // Strategy 3: Query any delegate with role 'companySupervisor' in this company
        if (permission.organizationUID.isNotEmpty && permission.companyUID.isNotEmpty) {
          final supDocs = await firestore
              .collection('organizations')
              .doc(permission.organizationUID)
              .collection('companies')
              .doc(permission.companyUID)
              .collection('delegates')
              .where('role', isEqualTo: 'companySupervisor')
              .limit(1)
              .get();
          if (supDocs.docs.isNotEmpty) {
            final res = extractInfo(supDocs.docs.first.data());
            if (res != null) return res;
          }
        }

        // Strategy 4: Fallback search in company document
        if (permission.organizationUID.isNotEmpty && permission.companyUID.isNotEmpty) {
          final compDoc = await firestore
              .collection('organizations')
              .doc(permission.organizationUID)
              .collection('companies')
              .doc(permission.companyUID)
              .get();
          if (compDoc.exists) {
            final data = compDoc.data();
            final phone = (data?['supervisorPhone'] ?? data?['phone'] ?? '').toString().trim();
            final name = (data?['supervisorName'] ?? data?['contactPerson'] ?? '').toString().trim();
            if (phone.isNotEmpty || name.isNotEmpty) {
              return {
                'name': name.isNotEmpty ? name : 'مشرف الشركة',
                'phone': phone,
                'companyName': permission.companyName,
              };
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching supervisor: $e');
      }
      return null;
    }

    final supervisorFuture = fetchSupervisorInfo();

    Widget buildContent(BuildContext modalContext) {
      final theme = Theme.of(modalContext);
      final colorScheme = theme.colorScheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          isDesktop ? 20 : 12,
          20,
          20 + MediaQuery.viewInsetsOf(modalContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isDesktop) _buildDragHandlePill(colorScheme),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_rounded, color: colorScheme.primary, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'بيانات مشرف الشركة',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        permission.companyName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            FutureBuilder<Map<String, dynamic>?>(
              future: supervisorFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('جاري البحث عن بيانات المشرف...'),
                        ],
                      ),
                    ),
                  );
                }

                final supervisor = snapshot.data;
                final name = supervisor?['name'] ?? 'مشرف الشركة';
                final phone = (supervisor?['phone'] ?? '').toString().trim();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.badge_rounded, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'اسم المشرف:',
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.phone_rounded, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'رقم الهاتف:',
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  phone.isNotEmpty ? phone : 'غير مسجل بالمنظومة',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: phone.isNotEmpty ? null : colorScheme.error,
                                  ),
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
                            ],
                          ),
                          if (permission.department != null && permission.department!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.category_rounded, size: 18, color: colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'القسم المصرح:',
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    permission.department!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (phone.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                Navigator.pop(modalContext);
                                _openPhone(phone);
                              },
                              icon: const Icon(Icons.call_rounded, size: 20),
                              label: const Text('اتصال هاتف', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                Navigator.pop(modalContext);
                                _openWhatsApp(phone);
                              },
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                              label: const Text('واتساب', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'لا يتوفر رقم هاتف مسجل لهذا المشرف في الوقت الحالي.',
                                style: TextStyle(fontSize: 12, color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildConnectedActionGroup(
              colorScheme: colorScheme,
              cancelLabel: 'إغلاق',
              onCancel: () => Navigator.pop(modalContext),
            ),
          ],
        ),
      );
    }

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: buildContent(dialogContext),
          ),
        ),
      );
    } else {
      showM3ModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) => buildContent(sheetContext),
      );
    }
  }

  Widget _buildPresetChip(
    StateSetter setModalState,
    String label,
    int days,
    DateTime startDate,
    DateTime currentEndDate,
    Function(DateTime) onSelect,
  ) {
    final targetDate = startDate.add(Duration(days: days));
    final isSelected = currentEndDate.year == targetDate.year &&
        currentEndDate.month == targetDate.month &&
        currentEndDate.day == targetDate.day;

    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      onPressed: () {
        setModalState(() {
          onSelect(targetDate);
        });
      },
    );
  }

  void _showEditDatesDialog(BuildContext parentContext, PhotoPermission permission) {
    final bloc = parentContext.read<PhotoPermissionBloc>();
    DateTime tempStart = permission.startDate;
    DateTime tempEnd = permission.endDate;
    final theme = Theme.of(parentContext);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final isDesktop = MediaQuery.sizeOf(parentContext).width > 768;

    Widget buildContent(BuildContext modalContext, StateSetter setModalState) {
      final diffDays = tempEnd.difference(tempStart).inDays;
      final isInvalid = tempEnd.isBefore(tempStart);

      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          isDesktop ? 20 : 12,
          20,
          20 + MediaQuery.viewInsetsOf(modalContext).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isDesktop) _buildDragHandlePill(colorScheme),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.edit_calendar_rounded, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'تعديل مدة إذن التصوير',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'الشركة: ${permission.companyName}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (permission.department != null && permission.department!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'القسم: ${permission.department}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // كرت اختيار تاريخ البداية
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: modalContext,
                    initialDate: tempStart,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    locale: const Locale('ar'),
                  );
                  if (picked != null) {
                    setModalState(() {
                      tempStart = picked;
                      if (tempEnd.isBefore(tempStart)) {
                        tempEnd = tempStart.add(const Duration(days: 30));
                      }
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                    color: colorScheme.surfaceContainerLow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تاريخ البداية:',
                            style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateFormat.format(tempStart),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Icon(Icons.calendar_today_rounded, size: 20, color: colorScheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // كرت اختيار تاريخ النهاية
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: modalContext,
                    initialDate: tempEnd.isBefore(tempStart) ? tempStart : tempEnd,
                    firstDate: tempStart,
                    lastDate: DateTime(2035),
                    locale: const Locale('ar'),
                  );
                  if (picked != null) {
                    setModalState(() {
                      tempEnd = picked;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                    color: colorScheme.surfaceContainerLow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تاريخ النهاية:',
                            style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateFormat.format(tempEnd),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Icon(Icons.event_available_rounded, size: 20, color: colorScheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // اختصارات المدد الشائعة
              Text(
                'مدد سريعة محددة:',
                style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPresetChip(setModalState, '30 يوم', 30, tempStart, tempEnd, (d) => tempEnd = d),
                    const SizedBox(width: 6),
                    _buildPresetChip(setModalState, '60 يوم', 60, tempStart, tempEnd, (d) => tempEnd = d),
                    const SizedBox(width: 6),
                    _buildPresetChip(setModalState, '90 يوم', 90, tempStart, tempEnd, (d) => tempEnd = d),
                    const SizedBox(width: 6),
                    _buildPresetChip(setModalState, '6 شهور', 180, tempStart, tempEnd, (d) => tempEnd = d),
                    const SizedBox(width: 6),
                    _buildPresetChip(setModalState, 'سنة', 365, tempStart, tempEnd, (d) => tempEnd = d),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // كرت عرض ملخص المدة المحتسبة
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isInvalid
                      ? colorScheme.errorContainer.withValues(alpha: 0.4)
                      : colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isInvalid ? 'تاريخ النهاية يسبق البداية!' : 'إجمالي عدد الأيام:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isInvalid ? colorScheme.error : colorScheme.primary,
                      ),
                    ),
                    if (!isInvalid)
                      Text(
                        '$diffDays يوم',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildConnectedActionGroup(
                colorScheme: colorScheme,
                cancelLabel: 'إلغاء',
                onCancel: () => Navigator.pop(modalContext),
                primaryLabel: 'حفظ المدة الجديدة',
                primaryIcon: Icons.check_rounded,
                onPrimary: isInvalid
                    ? null
                    : () {
                        Navigator.pop(modalContext);
                        bloc.add(
                          UpdatePhotoPermissionDatesRequested(
                            organizationUID: permission.organizationUID,
                            companyUID: permission.companyUID,
                            permissionId: permission.uid,
                            startDate: tempStart,
                            endDate: tempEnd,
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
      );
    }

    if (isDesktop) {
      showDialog(
        context: parentContext,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: StatefulBuilder(
              builder: (context, setModalState) => buildContent(dialogContext, setModalState),
            ),
          ),
        ),
      );
    } else {
      showM3ModalBottomSheet(
        context: parentContext,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setModalState) => buildContent(sheetContext, setModalState),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPinnedDepartments();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleExpandPermission(String id) {
    setState(() {
      if (_expandedPermissionIds.contains(id)) {
        _expandedPermissionIds.remove(id);
      } else {
        _expandedPermissionIds.add(id);
      }
    });
  }

  PhotoPermissionQueryScope get _queryScope => PhotoPermissionQueryScope.forRole(
        role: widget.marketingDelegate.role,
        organizationUID: widget.marketingDelegate.organizationUID,
        companyUID: widget.marketingDelegate.companyUID,
      );

  void _loadData() {
    final scope = _queryScope;
    if (!scope.shouldQuery) {
      setState(() {});
      return;
    }
    context.read<PhotoPermissionBloc>().add(
          LoadPermissionsRequested(
            organizationUID: scope.organizationUID,
            companyUID: scope.companyUID,
          ),
        );
  }

  Future<void> _confirmDeletePermission(BuildContext context, PhotoPermission permission) async {
    final isDesktop = MediaQuery.sizeOf(context).width > 768;
    final colorScheme = Theme.of(context).colorScheme;

    Widget buildContent(BuildContext modalContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          isDesktop ? 20 : 12,
          20,
          20 + MediaQuery.viewInsetsOf(modalContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isDesktop) _buildDragHandlePill(colorScheme),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 28),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'تأكيد حذف إذن التصوير',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'هل أنت متأكد من رغبتك في حذف إذن التصوير لشركة "${permission.companyName}" نهائياً؟',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم حذف هذا الإذن وجميع الصور الميدانية المرفوعة داخله بشكل نهائي لا يمكن التراجع عنه.',
                      style: TextStyle(fontSize: 12, color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _buildConnectedActionGroup(
              colorScheme: colorScheme,
              cancelLabel: 'إلغاء',
              onCancel: () => Navigator.pop(modalContext, false),
              primaryLabel: 'حذف نهائي',
              primaryIcon: Icons.delete_forever_rounded,
              primaryColor: colorScheme.error,
              onPrimary: () => Navigator.pop(modalContext, true),
            ),
          ],
        ),
      );
    }

    final bool? confirmed;
    if (isDesktop) {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: buildContent(dialogContext),
          ),
        ),
      );
    } else {
      confirmed = await showM3ModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) => buildContent(sheetContext),
      );
    }

    if (confirmed == true && context.mounted) {
      context.read<PhotoPermissionBloc>().add(
            DeletePhotoPermissionRequested(
              organizationUID: permission.organizationUID,
              companyUID: permission.companyUID,
              permissionId: permission.uid,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(
          !_canApproveOrReject
              ? 'أذونات التصوير النشطة'
              : 'إدارة واعتماد أذونات التصوير',
        ),
        centerTitle: true,
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث البيانات',
            onPressed: _loadData,
          ),
        ],
        bottom: _isPromotionUser
            ? TabBar(
                controller: _tabController,
                indicatorColor: colorScheme.primary,
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.pending_actions_rounded),
                    text: 'طلبات معلقة',
                  ),
                  Tab(
                    icon: Icon(Icons.verified_rounded),
                    text: 'الأذونات الجارية',
                  ),
                ],
              )
            : null,
      ),
      body: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        buildWhen: (previous, current) =>
            current is PhotoPermissionsLoaded ||
            current is OngoingPermissionsLoaded ||
            current is PhotoPermissionError ||
            (current is PhotoPermissionLoading &&
                previous is! PhotoPermissionsLoaded &&
                previous is! OngoingPermissionsLoaded &&
                previous is! PhotoPermissionError),
        listener: (context, state) {
          if (state is PermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _loadData();
          } else if (state is PhotoPermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _loadData();
          } else if (state is PhotoPermissionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          if (!_isPromotionUser) {
            return _buildOngoingTab(context, state, theme);
          }
          return TabBarView(
            controller: _tabController,
            children: [
              _buildPendingReviewTab(context, state, theme),
              _buildOngoingTab(context, state, theme),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDepartmentFilterPicker(BuildContext context, ThemeData theme) async {
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    Set<String> tempSelected = Set<String>.from(_selectedDepartments);
    bool tempPinned = _isPinned;

    Widget buildPickerContent(BuildContext modalContext, StateSetter setSheetState) {
      final isAll = tempSelected.isEmpty;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          isDesktop ? 20 : 12,
          20,
          24 + MediaQuery.viewInsetsOf(modalContext).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isDesktop) ...[
                _buildDragHandlePill(colorScheme),
                const SizedBox(height: 14),
              ],

              // Header Row
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'تصفية وتثبيت الأقسام',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (tempSelected.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setSheetState(() => tempSelected.clear());
                      },
                      icon: const Icon(Icons.clear_all_rounded, size: 16),
                      label: const Text('كل الأقسام', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'يمكنك اختيار أكثر من قسم معاً لعرضها وتثبيتها كفلتر افتراضي:',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Wrap of FilterChips for all 10 departments
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('كل الأقسام'),
                    avatar: isAll
                        ? const Icon(Icons.check_circle_rounded, size: 16)
                        : const Icon(Icons.apps_rounded, size: 16),
                    selected: isAll,
                    selectedColor: colorScheme.primaryContainer,
                    checkmarkColor: colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isAll ? colorScheme.primary : colorScheme.onSurface,
                      fontWeight: isAll ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (val) {
                      setSheetState(() => tempSelected.clear());
                    },
                  ),
                  ...kPhotoPermissionDepartments.map((dept) {
                    final isSelected = tempSelected.contains(dept);
                    return FilterChip(
                      label: Text(dept),
                      selected: isSelected,
                      selectedColor: colorScheme.primary,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : colorScheme.onSurface,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                      onSelected: (val) {
                        setSheetState(() {
                          if (val) {
                            tempSelected.add(dept);
                          } else {
                            tempSelected.remove(dept);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
              const SizedBox(height: 18),

              // Pin toggle card inside the selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: tempPinned
                      ? Colors.amber.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: tempPinned
                        ? Colors.amber.shade700
                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.push_pin_rounded,
                      size: 20,
                      color: tempPinned ? Colors.amber.shade900 : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tempPinned ? 'تثبيت الفلتر مفعل' : 'تثبيت الفلتر كافتراضي',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: tempPinned ? Colors.amber.shade900 : colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            tempSelected.isEmpty
                                ? 'سيتم فتح الشاشة دائماً على كل الأقسام'
                                : 'سيتم حفظ (${tempSelected.length}) أقسام كافتراضي عند فتح التطبيق',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: tempPinned,
                      activeTrackColor: Colors.amber.shade700,
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return null;
                      }),
                      onChanged: (val) {
                        setSheetState(() => tempPinned = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Connected Action Button Group
              _buildConnectedActionGroup(
                colorScheme: colorScheme,
                cancelLabel: 'إلغاء',
                onCancel: () => Navigator.pop(modalContext),
                primaryLabel: tempSelected.isEmpty
                    ? 'عرض كل الأقسام'
                    : 'تطبيق (${tempSelected.length} أقسام)',
                primaryIcon: Icons.check_rounded,
                primaryColor: colorScheme.primary,
                onPrimary: () async {
                  setState(() {
                    _selectedDepartments = tempSelected;
                    _isPinned = tempPinned;
                  });
                  final prefs = await SharedPreferences.getInstance();
                  final key = 'pinned_photo_departments_${widget.marketingDelegate.uid}';
                  if (tempPinned && tempSelected.isNotEmpty) {
                    await prefs.setStringList(key, tempSelected.toList());
                  } else {
                    await prefs.remove(key);
                    if (mounted) {
                      setState(() => _isPinned = false);
                    }
                  }
                  if (modalContext.mounted) {
                    Navigator.pop(modalContext);
                  }
                  if (context.mounted && tempPinned && tempSelected.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tempSelected.length == 1
                              ? 'تم تثبيت قسم (${tempSelected.first}) كفلتر افتراضي'
                              : 'تم تثبيت (${tempSelected.length}) أقسام كفلتر افتراضي',
                        ),
                        backgroundColor: colorScheme.primary,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (isDesktop) {
      await showDialog(
        context: context,
        builder: (dialogCtx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: StatefulBuilder(
              builder: (ctx, setSheetState) => buildPickerContent(dialogCtx, setSheetState),
            ),
          ),
        ),
      );
    } else {
      await showM3ModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetCtx) => StatefulBuilder(
          builder: (ctx, setSheetState) => buildPickerContent(sheetCtx, setSheetState),
        ),
      );
    }
  }

  Widget _buildDepartmentDropdownToolbar(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isSelectedAll = _selectedDepartments.isEmpty;
    final String currentLabel;
    if (isSelectedAll) {
      currentLabel = 'كل الأقسام';
    } else if (_selectedDepartments.length == 1) {
      currentLabel = _selectedDepartments.first;
    } else if (_selectedDepartments.length == 2) {
      currentLabel = _selectedDepartments.join(' + ');
    } else {
      currentLabel = '${_selectedDepartments.length} أقسام محددة';
    }

    return Row(
      children: [
        // زر القائمة المنسدلة لاختيار الأقسام
        Expanded(
          child: InkWell(
            onTap: () => _showDepartmentFilterPicker(context, theme),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: !isSelectedAll
                    ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: !isSelectedAll
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.category_rounded,
                    size: 18,
                    color: !isSelectedAll ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: !isSelectedAll ? colorScheme.primary : colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: !isSelectedAll ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // زر التثبيت في نفس الصف الأفقي
        InkWell(
          onTap: _togglePinCurrentFilter,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: AppMotionDurations.short3,
            curve: AppMotionCurves.standard,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _isPinned
                  ? Colors.amber.withValues(alpha: 0.15)
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isPinned
                    ? Colors.amber.shade700
                    : colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.push_pin_rounded,
                  size: 18,
                  color: _isPinned ? Colors.amber.shade900 : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  _isPinned
                      ? (_selectedDepartments.length > 1
                          ? 'مثبت (${_selectedDepartments.length})'
                          : 'مثبت')
                      : (_selectedDepartments.length > 1
                          ? 'تثبيت (${_selectedDepartments.length})'
                          : 'تثبيت الفلتر'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _isPinned ? FontWeight.bold : FontWeight.w600,
                    color: _isPinned ? Colors.amber.shade900 : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingReviewTab(BuildContext context, PhotoPermissionState state, ThemeData theme) {
    if (state is PhotoPermissionLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is PhotoPermissionError || !_queryScope.shouldQuery) {
      return _buildPermissionsLoadError(
        Theme.of(context),
        state is PhotoPermissionError
            ? state.message
            : 'لا يمكن عرض أذونات التصوير بدون منظمة أو شركة مرتبطة بالحساب.',
      );
    }

    if (state is PhotoPermissionsLoaded) {
      // فلترة الطلبات المعلقة فقط
      var pendingPermissions = state.permissions.where((p) => p.status == 'pending').toList();

      // فلترة حسب مجموعة الأقسام المحددة
      if (_selectedDepartments.isNotEmpty) {
        pendingPermissions = pendingPermissions.where((p) => p.department != null && _selectedDepartments.contains(p.department)).toList();
      }

      return Column(
        children: [
          // شريط فلترة الأقسام وخاصية التثبيت
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: _buildDepartmentDropdownToolbar(theme),
          ),
          const Divider(height: 1),
          Expanded(
            child: pendingPermissions.isEmpty
                ? _buildEmptyState(
                    theme,
                    _selectedDepartments.isNotEmpty
                        ? 'لا توجد طلبات تصوير معلقة في الأقسام المحددة'
                        : 'لا توجد طلبات تصوير معلقة حالياً',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: pendingPermissions.length,
                    itemBuilder: (context, index) {
                      final permission = pendingPermissions[index];
                      return _buildPendingCard(context, permission, theme);
                    },
                  ),
          ),
        ],
      );
    }

    return const Center(child: Text('جاري تحميل البيانات...'));
  }

  Widget _buildOngoingTab(BuildContext context, PhotoPermissionState state, ThemeData theme) {
    if (state is PhotoPermissionLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is PhotoPermissionError || !_queryScope.shouldQuery) {
      return _buildPermissionsLoadError(
        Theme.of(context),
        state is PhotoPermissionError
            ? state.message
            : 'لا يمكن عرض أذونات التصوير بدون منظمة أو شركة مرتبطة بالحساب.',
      );
    }

    if (state is OngoingPermissionsLoaded || state is PhotoPermissionsLoaded) {
      final permissions = state is OngoingPermissionsLoaded
          ? state.permissions
          : (state as PhotoPermissionsLoaded).permissions;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final activeList = permissions.where((p) =>
          p.status.toLowerCase() == 'approved' &&
          p.isSupervisorEnabled != false &&
          !p.startDate.isAfter(todayEnd) &&
          !p.endDate.isBefore(todayStart)).toList();

      final pendingList = permissions.where((p) => p.status.toLowerCase() == 'pending').toList();

      final expiredList = permissions.where((p) =>
          p.status.toLowerCase() == 'rejected' ||
          p.endDate.isBefore(todayStart) ||
          p.isSupervisorEnabled == false).toList();

      List<PhotoPermission> filtered = [];
      if (!_canApproveOrReject) {
        // مستخدم التسويق ليس له أحقية سوى في رؤية الأذونات النشطة فقط
        filtered = activeList;
      } else if (_selectedStatusFilter == 'active') {
        filtered = activeList;
      } else if (_selectedStatusFilter == 'pending') {
        filtered = pendingList;
      } else if (_selectedStatusFilter == 'expired') {
        filtered = expiredList;
      } else {
        filtered = permissions; // 'all'
      }

      // تصفية حسب مجموعة الأقسام المحددة
      if (_selectedDepartments.isNotEmpty) {
        filtered = filtered.where((p) => p.department != null && _selectedDepartments.contains(p.department)).toList();
      }

      // تصفية نتائج البحث باسم الشركة أو كود الشركة أو اسم الفرع أو القسم
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        filtered = filtered.where((p) {
          final matchName = p.companyName.toLowerCase().contains(query);
          final matchCode = p.companyCode != null && p.companyCode.toString().contains(query);
          final matchBranch = p.branchNames.any((b) => b.toLowerCase().contains(query));
          final matchDept = p.department != null && p.department!.toLowerCase().contains(query);
          return matchName || matchCode || matchBranch || matchDept;
        }).toList();
      }

      return Column(
        children: [
          // شريط البحث المعتمد وفق معايير Material 3
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: SearchBar(
              controller: _searchController,
              hintText: 'البحث بكود الشركة أو اسم الشركة',
              hintStyle: WidgetStatePropertyAll(
                theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              textStyle: WidgetStatePropertyAll(
                theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              leading: Icon(
                Icons.search_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              trailing: [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    tooltip: 'مسح البحث',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
              ],
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ),
              side: WidgetStatePropertyAll(
                BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1.0,
                ),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // فلاتر الحالة (تظهر فقط لمن له صلاحية الاعتماد والإدارة - أما موظف التسويق فيرى النشطة فقط بدون فلتر)
          if (_canApproveOrReject)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('الكل (${permissions.length})'),
                      selected: _selectedStatusFilter == 'all',
                      onSelected: (val) {
                        if (val) setState(() => _selectedStatusFilter = 'all');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('النشطة (${activeList.length})'),
                      selected: _selectedStatusFilter == 'active',
                      selectedColor: Colors.green.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: _selectedStatusFilter == 'active' ? Colors.green.shade800 : null,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedStatusFilter = 'active');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('المعلقة (${pendingList.length})'),
                      selected: _selectedStatusFilter == 'pending',
                      selectedColor: Colors.orange.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: _selectedStatusFilter == 'pending' ? Colors.orange.shade800 : null,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedStatusFilter = 'pending');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('المنتهية / المرفوضة (${expiredList.length})'),
                      selected: _selectedStatusFilter == 'expired',
                      selectedColor: Colors.red.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: _selectedStatusFilter == 'expired' ? Colors.red.shade800 : null,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedStatusFilter = 'expired');
                      },
                    ),
                  ],
                ),
              ),
            ),

          // شريط فلترة الأقسام وخاصية التثبيت
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: _buildDepartmentDropdownToolbar(theme),
          ),

          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState(
                    theme,
                    _searchQuery.isNotEmpty
                        ? 'لا توجد نتائج تطابق "$_searchQuery"'
                        : (_selectedDepartments.isNotEmpty
                            ? 'لا توجد أذونات تصوير في الأقسام المحددة'
                            : (!_canApproveOrReject
                                ? 'لا توجد أذونات تصوير نشطة في الوقت الحالي'
                                : 'لا توجد أذونات تصوير في الوقت الحالي')),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final permission = filtered[index];
                      return _buildOngoingCard(context, permission, theme);
                    },
                  ),
          ),
        ],
      );
    }

    return const Center(child: Text('جاري تحميل الأذونات الجارية...'));
  }

  Widget _buildEmptyState(ThemeData theme, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(BuildContext context, PhotoPermission permission, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final daysCount = permission.endDate.difference(permission.startDate).inDays;
    final isExpanded = _expandedPermissionIds.contains(permission.uid);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLow,
      elevation: isExpanded ? 2.5 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isExpanded
              ? colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isExpanded ? 1.2 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _toggleExpandPermission(permission.uid),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // السطر الرئيسي: اسم الشركة والكود على اليمين وشارة الحالة مع سهم التوسيع على اليسار
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CompanyNameWithCode(
                      organizationUID: permission.organizationUID.isNotEmpty
                          ? permission.organizationUID
                          : widget.marketingDelegate.organizationUID,
                      companyUID: permission.companyUID,
                      companyName: permission.companyName,
                      companyCode: permission.companyCode,
                      twoLines: true,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                      codeStyle: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 13, color: Colors.orange),
                            SizedBox(width: 4),
                            Text(
                              'في انتظار الاعتماد',
                              style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: AppMotionDurations.short4,
                        curve: AppMotionCurves.emphasized,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // السطر الثاني: القسم على اليمين وشيبس "بواسطة" على أقصى الشمال
              if ((permission.department != null && permission.department!.isNotEmpty) ||
                  (permission.approvedBy != null && permission.approvedBy!.trim().isNotEmpty)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (permission.department != null && permission.department!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.category_rounded, size: 11, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'القسم: ${permission.department}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    if (permission.approvedBy != null && permission.approvedBy!.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.25),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_rounded, size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width * 0.48,
                              ),
                              child: ApproverNameText(
                                approvedBy: permission.approvedBy!,
                                organizationUID: permission.organizationUID.isNotEmpty
                                    ? permission.organizationUID
                                    : widget.marketingDelegate.organizationUID,
                                companyUID: permission.companyUID,
                                currentUserUid: widget.marketingDelegate.uid,
                                currentUserName: widget.marketingDelegate.fullName,
                                prefix: '',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],

              // التفاصيل المنسدلة عند النقر عبر M3 Motion
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 18),
                    // سطر التواريخ وتعديل المدة
                    InkWell(
                      onTap: _canEditDates ? () => _showEditDatesDialog(context, permission) : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.date_range_rounded, size: 16, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'من: ${dateFormat.format(permission.startDate)}  -  إلى: ${dateFormat.format(permission.endDate)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '($daysCount يوم)',
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11.5),
                            ),
                            if (_canEditDates) ...[
                              const Spacer(),
                              Icon(Icons.edit_calendar_rounded, size: 16, color: colorScheme.primary),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // زر الفروع المعتمدة المدمج
                    InkWell(
                      onTap: () => _showBranchesDialog(context, permission.companyName, permission.branchNames),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.store_rounded, size: 15, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'الفروع المطلوبة للتصوير (${permission.branchNames.length})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.visibility_rounded, size: 14, color: colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 18),
                    // صف أزرار الموافقة والرفض والتواصل
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _showSupervisorDialog(context, permission),
                              icon: Icon(Icons.phone_in_talk_rounded, color: colorScheme.primary, size: 20),
                              tooltip: 'تواصل مع مشرف الشركة',
                              style: IconButton.styleFrom(
                                backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(36, 36),
                              ),
                            ),
                            if (_isSuperAdmin || _isTechnicalSupport) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: () => _confirmDeletePermission(context, permission),
                                tooltip: 'حذف الإذن نهائياً',
                                icon: Icon(Icons.delete_forever_rounded, color: Colors.red.shade700, size: 20),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red.withValues(alpha: 0.1),
                                  padding: const EdgeInsets.all(8),
                                  minimumSize: const Size(36, 36),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_canApproveOrReject)
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  context.read<PhotoPermissionBloc>().add(
                                        ApprovePermissionRequested(
                                          organizationUID: permission.organizationUID,
                                          companyUID: permission.companyUID,
                                          permissionId: permission.uid,
                                          status: 'rejected',
                                          approvedBy: _approverText,
                                        ),
                                      );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 16),
                                label: const Text('رفض', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  context.read<PhotoPermissionBloc>().add(
                                    ApprovePermissionRequested(
                                      organizationUID: permission.organizationUID,
                                      companyUID: permission.companyUID,
                                      permissionId: permission.uid,
                                      status: 'approved',
                                      approvedBy: _approverText,
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('اعتماد', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
                crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: AppMotionDurations.medium2,
                reverseDuration: AppMotionDurations.short4,
                firstCurve: AppMotionCurves.emphasizedAccelerate,
                secondCurve: AppMotionCurves.emphasizedDecelerate,
                sizeCurve: AppMotionCurves.emphasized,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOngoingCard(BuildContext context, PhotoPermission permission, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final daysCount = permission.endDate.difference(permission.startDate).inDays;
    final isExpanded = _expandedPermissionIds.contains(permission.uid);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLow,
      elevation: isExpanded ? 2.5 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isExpanded
              ? colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isExpanded ? 1.2 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _toggleExpandPermission(permission.uid),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // السطر الرئيسي: اسم الشركة والكود على اليمين وشارة الحالة مع سهم التوسيع على اليسار
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CompanyNameWithCode(
                      organizationUID: permission.organizationUID.isNotEmpty
                          ? permission.organizationUID
                          : widget.marketingDelegate.organizationUID,
                      companyUID: permission.companyUID,
                      companyName: permission.companyName,
                      companyCode: permission.companyCode,
                      twoLines: true,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                      codeStyle: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusBadge(permission),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: AppMotionDurations.short4,
                        curve: AppMotionCurves.emphasized,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // السطر الثاني: القسم على اليمين وشيبس "بواسطة" على أقصى الشمال
              if ((permission.department != null && permission.department!.isNotEmpty) ||
                  (permission.approvedBy != null && permission.approvedBy!.trim().isNotEmpty)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (permission.department != null && permission.department!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.category_rounded, size: 11, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'القسم: ${permission.department}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    if (permission.approvedBy != null && permission.approvedBy!.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.25),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_rounded, size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width * 0.48,
                              ),
                              child: ApproverNameText(
                                approvedBy: permission.approvedBy!,
                                organizationUID: permission.organizationUID.isNotEmpty
                                    ? permission.organizationUID
                                    : widget.marketingDelegate.organizationUID,
                                companyUID: permission.companyUID,
                                currentUserUid: widget.marketingDelegate.uid,
                                currentUserName: widget.marketingDelegate.fullName,
                                prefix: '',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],

              // التفاصيل المنسدلة عند النقر عبر M3 Motion
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 18),
                    // سطر التواريخ وتعديل المدة
                    InkWell(
                      onTap: _canEditDates ? () => _showEditDatesDialog(context, permission) : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.date_range_rounded, size: 16, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'من: ${dateFormat.format(permission.startDate)}  -  إلى: ${dateFormat.format(permission.endDate)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '($daysCount يوم)',
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11.5),
                            ),
                            if (_canEditDates) ...[
                              const Spacer(),
                              Icon(Icons.edit_calendar_rounded, size: 16, color: colorScheme.primary),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // زر الفروع المعتمدة المدمج
                    InkWell(
                      onTap: () => _showBranchesDialog(context, permission.companyName, permission.branchNames),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.store_rounded, size: 15, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'الفروع المعتمدة (${permission.branchNames.length})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.visibility_rounded, size: 14, color: colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
                    if (permission.status.toLowerCase() == 'pending' && _canApproveOrReject) ...[
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              context.read<PhotoPermissionBloc>().add(
                                    ApprovePermissionRequested(
                                      organizationUID: permission.organizationUID,
                                      companyUID: permission.companyUID,
                                      permissionId: permission.uid,
                                      status: 'rejected',
                                      approvedBy: _approverText,
                                    ),
                                  );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('رفض', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              context.read<PhotoPermissionBloc>().add(
                                    ApprovePermissionRequested(
                                      organizationUID: permission.organizationUID,
                                      companyUID: permission.companyUID,
                                      permissionId: permission.uid,
                                      status: 'approved',
                                      approvedBy: _approverText,
                                    ),
                                  );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('الموافقة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    // صف أزرار الإجراءات والاتصال
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            // أيقونة الاتصال بمشرف الشركة جنب الـ Delete
                            IconButton(
                              onPressed: () => _showSupervisorDialog(context, permission),
                              icon: Icon(Icons.phone_in_talk_rounded, color: colorScheme.primary, size: 20),
                              tooltip: 'تواصل مع مشرف الشركة',
                              style: IconButton.styleFrom(
                                backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(36, 36),
                              ),
                            ),
                            if (_isPromotionUser || _isTechnicalSupport || _isSuperAdmin) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: () => _confirmDeletePermission(context, permission),
                                icon: Icon(Icons.delete_rounded, color: colorScheme.error, size: 20),
                                tooltip: 'حذف الإذن',
                                style: IconButton.styleFrom(
                                  backgroundColor: colorScheme.error.withValues(alpha: 0.1),
                                  padding: const EdgeInsets.all(8),
                                  minimumSize: const Size(36, 36),
                                ),
                              ),
                            ],
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (routeContext) => BlocProvider(
                                  create: (_) => di.sl<PhotoPermissionBloc>(),
                                  child: CapturedPhotosViewScreen(
                                    photoPermission: permission,
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.collections_rounded, size: 17),
                          label: const Text('عرض الصور الميدانية', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
                crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: AppMotionDurations.medium2,
                reverseDuration: AppMotionDurations.short4,
                firstCurve: AppMotionCurves.emphasizedAccelerate,
                secondCurve: AppMotionCurves.emphasizedDecelerate,
                sizeCurve: AppMotionCurves.emphasized,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(PhotoPermission permission) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final status = permission.status.toLowerCase();

    Widget badge;
    if (status == 'pending') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
        ),
        child: Text(
          'في انتظار الاعتماد',
          style: TextStyle(color: colorScheme.onTertiaryContainer, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else if (status == 'rejected') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Text(
          'مرفوض',
          style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else if (permission.endDate.isBefore(todayStart)) {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Text(
          'منتهي',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else if (permission.isSupervisorEnabled == false) {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
        ),
        child: Text(
          'معطل مؤقتاً',
          style: TextStyle(color: colorScheme.onSecondaryContainer, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          'نشط',
          style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    }
    return badge;
  }

  Widget _buildPermissionsLoadError(ThemeData theme, String message) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
