import 'supervisor_permissions_screen.dart';
import '../widgets/company_name_with_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';
import 'captured_photos_view_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MarketingPermissionsScreen extends StatefulWidget {
  final Delegate marketingDelegate;

  const MarketingPermissionsScreen({super.key, required this.marketingDelegate});

  @override
  State<MarketingPermissionsScreen> createState() => _MarketingPermissionsScreenState();
}

class _MarketingPermissionsScreenState extends State<MarketingPermissionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedStatusFilter = 'all'; // 'all', 'active', 'pending', 'expired'

  bool get _isPromotionUser =>
      widget.marketingDelegate.role == UserRole.marketingPromotion ||
      widget.marketingDelegate.role == UserRole.superAdmin;

  bool get _isSuperAdmin => widget.marketingDelegate.role == UserRole.superAdmin;
  bool get _isTechnicalSupport =>
      widget.marketingDelegate.role == UserRole.technicalSupport;

  bool get _canApproveOrReject =>
      widget.marketingDelegate.role == UserRole.marketingPromotion ||
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

  void _showSupervisorDialog(BuildContext context, PhotoPermission permission) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;

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
                final userData = userDoc.data();
                final orgId = userData?['organizationUID']?.toString() ?? permission.organizationUID;
                final compId = userData?['companyUID']?.toString() ?? permission.companyUID;

                if (orgId.isNotEmpty && compId.isNotEmpty) {
                  final delDoc = await firestore
                      .collection('organizations')
                      .doc(orgId)
                      .collection('companies')
                      .doc(compId)
                      .collection('delegates')
                      .doc(permission.requestedBy)
                      .get();
                  if (delDoc.exists) {
                    final info = extractInfo(delDoc.data());
                    if (info != null) return info;
                  }
                }

                final info = extractInfo(userData);
                if (info != null) return info;
              }

              // Strategy 2: Direct delegate path with permission's org & company
              if (permission.organizationUID.isNotEmpty && permission.companyUID.isNotEmpty) {
                final delDoc = await firestore
                    .collection('organizations')
                    .doc(permission.organizationUID)
                    .collection('companies')
                    .doc(permission.companyUID)
                    .collection('delegates')
                    .doc(permission.requestedBy)
                    .get();
                if (delDoc.exists) {
                  final info = extractInfo(delDoc.data());
                  if (info != null) return info;
                }
              }

              // Strategy 3: collectionGroup search by document ID
              final groupQuery = await firestore
                  .collectionGroup('delegates')
                  .where(FieldPath.documentId, isEqualTo: permission.requestedBy)
                  .limit(1)
                  .get();
              if (groupQuery.docs.isNotEmpty) {
                final info = extractInfo(groupQuery.docs.first.data());
                if (info != null) return info;
              }
            }

            // Strategy 4: Find supervisor delegate in permission's company subcollection
            if (permission.organizationUID.isNotEmpty && permission.companyUID.isNotEmpty) {
              final supervisorQuery = await firestore
                  .collection('organizations')
                  .doc(permission.organizationUID)
                  .collection('companies')
                  .doc(permission.companyUID)
                  .collection('delegates')
                  .where('position', whereIn: ['supervisor', 'Supervisor', 'مباشر', 'مشرف'])
                  .limit(1)
                  .get();
              if (supervisorQuery.docs.isNotEmpty) {
                final info = extractInfo(supervisorQuery.docs.first.data());
                if (info != null) return info;
              }

              // Strategy 5: Any delegate doc under that company
              final anyDelegate = await firestore
                  .collection('organizations')
                  .doc(permission.organizationUID)
                  .collection('companies')
                  .doc(permission.companyUID)
                  .collection('delegates')
                  .limit(1)
                  .get();
              if (anyDelegate.docs.isNotEmpty) {
                final info = extractInfo(anyDelegate.docs.first.data());
                if (info != null) return info;
              }
            }

            // Strategy 6: Find company via collectionGroup if orgUID was empty, then get any supervisor/delegate
            if (permission.companyUID.isNotEmpty) {
              final companyQuery = await firestore
                  .collectionGroup('companies')
                  .where(FieldPath.documentId, isEqualTo: permission.companyUID)
                  .limit(1)
                  .get();
              if (companyQuery.docs.isNotEmpty) {
                final companyRef = companyQuery.docs.first.reference;
                final delegatesQuery = await companyRef.collection('delegates').limit(5).get();
                for (final doc in delegatesQuery.docs) {
                  final info = extractInfo(doc.data());
                  if (info != null) return info;
                }
              }
            }
          } catch (e) {
            debugPrint('Error fetching supervisor: $e');
          }

          return null;
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: colorScheme.surfaceContainerHigh,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_pin_rounded, color: colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('مشرف الشركة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: FutureBuilder<Map<String, dynamic>?>(
            future: fetchSupervisorInfo(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final info = snapshot.data;
              if (info == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('لم يتم العثور على بيانات مشرف هذه الشركة.'),
                );
              }

              final displayName = info['name'] as String;
              final phone = info['phone'] as String;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: colorScheme.secondaryContainer,
                      child: Icon(Icons.person_rounded, color: colorScheme.onSecondaryContainer),
                    ),
                    title: Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      permission.companyName,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.phone_android_rounded, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          phone,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colorScheme.onSurface,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Material Design 3 Button Group
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _openPhone(phone);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.call_rounded, size: 18),
                              label: const Text('اتصال', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _openWhatsApp(phone);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.25),
                                foregroundColor: const Color(0xFF075E54),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.chat_rounded, size: 18),
                              label: const Text('واتساب', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    const Text('لا يوجد رقم هاتف مسجل للمشرف.'),
                  ],
                ],
              );
            },
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  void _loadData() {
    // جلب كافة أذونات التصوير عبر النظام بالكامل لفرع التسويق بدون التقييد بالمنظمة
    context.read<PhotoPermissionBloc>().add(
          const LoadPermissionsRequested(
            organizationUID: '', // فارغة لعدم التقييد بأي منظمة
            companyUID: '',      // فارغة لعدم التقييد بأي شركة
          ),
        );
  }

  Future<void> _confirmDeletePermission(BuildContext context, PhotoPermission permission) async {
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
                'تأكيد حذف إذن التصوير',
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
              'هل أنت متأكد من رغبتك في حذف إذن التصوير لشركة "${permission.companyName}" نهائياً؟',
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
                      'سيتم حذف هذا الإذن وجميع الصور الميدانية المرفوعة داخله بشكل نهائي لا يمكن التراجع عنه.',
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isPromotionUser ? 'أذونات تصوير الشركات' : 'أذونات التصوير',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: _isPromotionUser
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'طلبات معلقة'),
                  Tab(text: 'الأذونات الجارية'),
                ],
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      body: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        listener: (context, state) {
          if (state is PermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _loadData();
          } else if (state is PhotoPermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
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

  Widget _buildPendingReviewTab(BuildContext context, PhotoPermissionState state, ThemeData theme) {
    if (state is PhotoPermissionLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is PhotoPermissionsLoaded) {
      // فلترة الطلبات المعلقة فقط
      final pendingPermissions = state.permissions.where((p) => p.status == 'pending').toList();

      if (pendingPermissions.isEmpty) {
        return _buildEmptyState(theme, 'لا توجد طلبات تصوير معلقة حالياً');
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: pendingPermissions.length,
        itemBuilder: (context, index) {
          final permission = pendingPermissions[index];
          return _buildPendingCard(context, permission, theme);
        },
      );
    }

    return const Center(child: Text('جاري تحميل البيانات...'));
  }

  String _searchQuery = '';

  Widget _buildOngoingTab(BuildContext context, PhotoPermissionState state, ThemeData theme) {
    if (state is PhotoPermissionLoading) {
      return const Center(child: CircularProgressIndicator());
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
      if (_selectedStatusFilter == 'active') {
        filtered = activeList;
      } else if (_selectedStatusFilter == 'pending') {
        filtered = pendingList;
      } else if (_selectedStatusFilter == 'expired') {
        filtered = expiredList;
      } else {
        filtered = permissions; // 'all'
      }

      // تصفية نتائج البحث باسم الشركة أو كود الشركة أو اسم الفرع
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        filtered = filtered.where((p) {
          final matchName = p.companyName.toLowerCase().contains(query);
          final matchCode = p.companyCode != null && p.companyCode.toString().contains(query);
          final matchBranch = p.branchNames.any((b) => b.toLowerCase().contains(query));
          return matchName || matchCode || matchBranch;
        }).toList();
      }

      return Column(
        children: [
          // شريط البحث المتقدم بكود الشركة والاسم والفرع
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'ابحث بكود الشركة، اسم الشركة، أو الفرع...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
          ),

          // فلاتر الحالة
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

          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState(
                    theme,
                    _searchQuery.isNotEmpty
                        ? 'لا توجد نتائج تطابق "$_searchQuery"'
                        : 'لا توجد أذونات تصوير في الوقت الحالي',
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: CompanyNameWithCode(
            organizationUID: permission.organizationUID.isNotEmpty
                ? permission.organizationUID
                : widget.marketingDelegate.organizationUID,
            companyUID: permission.companyUID,
            companyName: permission.companyName,
            companyCode: permission.companyCode,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'في انتظار الاعتماد ⏳',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          children: [
            const Divider(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الفترة المطلوبة ($daysCount يوم):',
                style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.date_range_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'من: ${dateFormat.format(permission.startDate)}  -  إلى: ${dateFormat.format(permission.endDate)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الفروع المطلوبة للتصوير (${permission.branchNames.length}):',
                style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
            ExpandableBranchText(branchNames: permission.branchNames),
            const SizedBox(height: 12),
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('organizations')
                  .doc(permission.organizationUID)
                  .collection('companies')
                  .doc(permission.companyUID)
                  .collection('delegates')
                  .doc(permission.requestedBy)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const SizedBox.shrink();
                }
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final name = data['fullName'] ?? data['firstName'] ?? 'غير معروف';
                final phone = data['phoneNumber'] ?? '';

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(Icons.person, color: colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'طلب بواسطة: $name',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            if (phone.isNotEmpty)
                              Text(
                                phone,
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                                textDirection: TextDirection.ltr,
                              ),
                          ],
                        ),
                      ),
                      if (phone.isNotEmpty)
                        IconButton(
                          onPressed: () async {
                            final url = Uri.parse('tel:$phone');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            }
                          },
                          icon: const Icon(Icons.call),
                          color: Colors.green,
                          tooltip: 'اتصال',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.green.withValues(alpha: 0.1),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isSuperAdmin || _isTechnicalSupport) ...[
                  IconButton(
                    onPressed: () => _confirmDeletePermission(context, permission),
                    tooltip: 'حذف الإذن نهائياً',
                    icon: Icon(Icons.delete_forever_rounded, color: Colors.red.shade700),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                    ),
                  ),
                  const Spacer(),
                ],
                if (_canApproveOrReject) ...[
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('رفض'),
                  ),
                  const SizedBox(width: 12),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('الموافقة'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOngoingCard(BuildContext context, PhotoPermission permission, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final daysCount = permission.endDate.difference(permission.startDate).inDays;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CompanyNameWithCode(
                        organizationUID: permission.organizationUID.isNotEmpty
                            ? permission.organizationUID
                            : widget.marketingDelegate.organizationUID,
                        companyUID: permission.companyUID,
                        companyName: permission.companyName,
                        companyCode: permission.companyCode,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(permission),
              ],
            ),
            const Divider(height: 24),
            Text(
              'صلاحية الإذن ($daysCount يوم):',
              style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'من: ${dateFormat.format(permission.startDate)}  -  إلى: ${dateFormat.format(permission.endDate)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'الفروع المعتمدة (${permission.branchNames.length}):',
              style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            ExpandableBranchText(branchNames: permission.branchNames),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _showSupervisorDialog(context, permission),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(Icons.person, color: colorScheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'مشرف الشركة (اضغط للتواصل)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 13),
                      ),
                    ),
                    Icon(Icons.phone_outlined, color: colorScheme.primary, size: 20),
                  ],
                ),
              ),
            ),
            if (permission.status.toLowerCase() == 'pending' && _canApproveOrReject) ...[
              const Divider(height: 20),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('رفض'),
                  ),
                  const SizedBox(width: 12),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('الموافقة'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (_isPromotionUser || _isTechnicalSupport || _isSuperAdmin)
                      IconButton(
                        onPressed: () => _confirmDeletePermission(context, permission),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'حذف الإذن',
                      ),
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
                  icon: const Icon(Icons.collections_rounded, size: 18),
                  label: const Text('عرض الصور الميدانية المرفوعة'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(PhotoPermission permission) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final status = permission.status.toLowerCase();

    Widget badge;
    if (status == 'pending') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: const Text(
          'في انتظار الاعتماد ⏳',
          style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    } else if (status == 'rejected') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: const Text(
          'مرفوض 🔴',
          style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    } else if (permission.endDate.isBefore(todayStart)) {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: const Text(
          'منتهي 🔴',
          style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    } else if (permission.isSupervisorEnabled == false) {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade400),
        ),
        child: const Text(
          'معطل مؤقتاً ⏸️',
          style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: const Text(
          'نشط 🟢',
          style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    }

    if (permission.approvedBy != null && permission.approvedBy!.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          badge,
          const SizedBox(height: 4),
          ApproverNameText(
            approvedBy: permission.approvedBy!,
            organizationUID: widget.marketingDelegate.organizationUID,
            companyUID: permission.companyUID,
            currentUserUid: widget.marketingDelegate.uid,
            currentUserName: widget.marketingDelegate.fullName,
            prefix: permission.status == 'approved'
                ? 'بواسطة: '
                : 'مرفوض بواسطة: ',
            style: TextStyle(
              color: permission.status == 'approved' ? Colors.green.shade700 : Colors.red.shade700,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return badge;
  }
}

class ExpandableBranchText extends StatefulWidget {
  final List<String> branchNames;

  const ExpandableBranchText({super.key, required this.branchNames});

  @override
  State<ExpandableBranchText> createState() => _ExpandableBranchTextState();
}

class _ExpandableBranchTextState extends State<ExpandableBranchText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.branchNames.join('، ');

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
            style: theme.textTheme.bodyMedium,
            maxLines: _isExpanded ? null : 3,
            overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (text.length > 70 || widget.branchNames.length > 2) ...[
            const SizedBox(height: 4),
            Text(
              _isExpanded ? 'عرض أقل ▲' : 'عرض المزيد... ▼',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
