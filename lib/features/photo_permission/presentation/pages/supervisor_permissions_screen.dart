import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../widgets/company_name_with_code.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';
import 'captured_photos_view_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

class SupervisorPermissionsScreen extends StatefulWidget {
  final Delegate supervisorDelegate;
  final bool showAppBar;

  const SupervisorPermissionsScreen({
    super.key,
    required this.supervisorDelegate,
    this.showAppBar = true,
  });

  @override
  State<SupervisorPermissionsScreen> createState() => _SupervisorPermissionsScreenState();
}

class _SupervisorPermissionsScreenState extends State<SupervisorPermissionsScreen> {
  String _selectedFilter = 'all'; // Options: 'all', 'active', 'pending', 'expired'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    context.read<PhotoPermissionBloc>().add(
          LoadPermissionsRequested(
            organizationUID: widget.supervisorDelegate.organizationUID,
            companyUID: widget.supervisorDelegate.companyUID,
          ),
        );
    context.read<BranchBloc>().add(BranchLoadRequested());
  }

  bool get _isSuperAdmin => widget.supervisorDelegate.role == UserRole.superAdmin;

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(
                'أذونات التصوير',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadData,
                ),
              ],
            )
          : null,
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
          if (state is PhotoPermissionLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is PhotoPermissionsLoaded) {
            final permissions = state.permissions;
            if (permissions.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => _loadData(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: _buildEmptyState(theme),
                    ),
                  ],
                ),
              );
            }

            final now = DateTime.now();
            final todayStart = DateTime(now.year, now.month, now.day);

            final activeList = permissions.where((p) =>
                p.status.toLowerCase() == 'approved' && !p.endDate.isBefore(todayStart)).toList();
            final pendingList = permissions.where((p) =>
                p.status.toLowerCase() == 'pending').toList();
            final expiredList = permissions.where((p) =>
                p.status.toLowerCase() == 'rejected' || p.endDate.isBefore(todayStart)).toList();

            List<PhotoPermission> filteredList;
            switch (_selectedFilter) {
              case 'active':
                filteredList = activeList;
                break;
              case 'pending':
                filteredList = pendingList;
                break;
              case 'expired':
                filteredList = expiredList;
                break;
              case 'all':
              default:
                filteredList = permissions;
                break;
            }

            return Column(
              children: [
                // Filter Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: colorScheme.surface,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'الكل (${permissions.length})', theme),
                        const SizedBox(width: 8),
                        _buildFilterChip('active', 'النشطة (${activeList.length})', theme),
                        const SizedBox(width: 8),
                        _buildFilterChip('pending', 'المعلقة (${pendingList.length})', theme),
                        const SizedBox(width: 8),
                        _buildFilterChip('expired', 'المنتهية (${expiredList.length})', theme),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => _loadData(),
                    child: filteredList.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: _buildEmptyFilteredState(theme),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredList.length,
                            itemBuilder: (context, index) {
                              return _buildPermissionCard(context, filteredList[index], theme);
                            },
                          ),
                  ),
                ),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _loadData(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: const Center(child: Text('اضغط على تحديث لجلب البيانات.')),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: widget.supervisorDelegate.role == UserRole.organizationAdmin
          ? null
          : FloatingActionButton.extended(
              heroTag: 'supervisor_permissions_fab',
              onPressed: () => _showCreateRequestSheet(context),
              label: const Text('طلب إذن تصوير'),
              icon: const Icon(Icons.add_a_photo_rounded),
            ),
    );
  }

  Widget _buildFilterChip(String key, String label, ThemeData theme) {
    final isSelected = _selectedFilter == key;
    final colorScheme = theme.colorScheme;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
        ),
      ),
      selected: isSelected,
      selectedColor: colorScheme.primary,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFilter = key;
          });
        }
      },
    );
  }

  Widget _buildEmptyFilteredState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off_rounded,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'لا توجد أذونات تطابق هذا الفلتر',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.no_photography_rounded,
            size: 80,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد أذونات تصوير مسجلة',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (widget.supervisorDelegate.role != UserRole.organizationAdmin) ...[
            const SizedBox(height: 8),
            Text(
              'اضغط على الزر بالأسفل لطلب إذن جديد لشركتك.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionCard(BuildContext context, PhotoPermission permission, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final isApproved = permission.status == 'approved';
    final daysCount = permission.endDate.difference(permission.startDate).inDays;

    Color statusColor;
    String statusText;

    switch (permission.status) {
      case 'approved':
        statusColor = Colors.green;
        statusText = 'مقبول';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusText = 'مرفوض';
        break;
      case 'pending':
      default:
        statusColor = Colors.orange;
        statusText = 'معلق';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        key: ValueKey(permission.uid),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanyNameWithCode(
                      organizationUID: permission.organizationUID.isNotEmpty
                          ? permission.organizationUID
                          : widget.supervisorDelegate.organizationUID,
                      companyUID: permission.companyUID,
                      companyName: permission.companyName,
                      companyCode: permission.companyCode,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (permission.approvedBy != null &&
                        permission.approvedBy!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            permission.status == 'approved'
                                ? Icons.verified_user_rounded
                                : Icons.person_outline_rounded,
                            size: 13,
                            color: permission.status == 'approved'
                                ? Colors.green.shade700
                                : colorScheme.error,
                          ),
                          const SizedBox(width: 4),
                          ApproverNameText(
                            approvedBy: permission.approvedBy!,
                            organizationUID: widget.supervisorDelegate.organizationUID,
                            companyUID: permission.companyUID,
                            currentUserUid: widget.supervisorDelegate.uid,
                            currentUserName: widget.supervisorDelegate.fullName,
                            prefix: permission.status == 'approved'
                                ? 'تم الاعتماد بواسطة: '
                                : 'مرفوض بواسطة: ',
                            style: TextStyle(
                              color: permission.status == 'approved'
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (isApproved && widget.supervisorDelegate.role == UserRole.marketingPromotion)
                  Row(
                    children: [
                      Text(
                        permission.isSupervisorEnabled ? 'مفعّل للمناديب' : 'معطّل مؤقتاً',
                        style: TextStyle(
                          fontSize: 12,
                          color: permission.isSupervisorEnabled
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: permission.isSupervisorEnabled,
                        onChanged: (val) {
                          context.read<PhotoPermissionBloc>().add(
                                TogglePermissionRequested(
                                  organizationUID: permission.organizationUID,
                                  companyUID: permission.companyUID,
                                  permissionId: permission.uid,
                                  isEnabled: val,
                                ),
                              );
                        },
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'الفترة المصرحة ($daysCount يوم):',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'من: ${dateFormat.format(permission.startDate)}  -  إلى: ${dateFormat.format(permission.endDate)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'الفروع المعتمدة (${permission.branchNames.length}):',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            ExpandableBranchText(branchNames: permission.branchNames),
            if (isApproved || _isSuperAdmin) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_isSuperAdmin)
                    IconButton(
                      onPressed: () => _confirmDeletePermission(context, permission),
                      tooltip: 'حذف الإذن نهائياً',
                      icon: Icon(Icons.delete_forever_rounded, color: Colors.red.shade700, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                      ),
                    )
                  else
                    Text(
                      'متابعة المناديب وتقارير الصور:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (isApproved)
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
                      label: const Text('عرض الصور الميدانية'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCreateRequestSheet(BuildContext context) {
    if (widget.supervisorDelegate.role == UserRole.organizationAdmin) return;
    final state = context.read<PhotoPermissionBloc>().state;
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
          const SnackBar(
            content: Text('⚠️ يوجد بالفعل إذن تصوير فعال أو معلق قيد المراجعة لهذه الشركة. لا يمكن تقديم طلب جديد حتى انتهاء الإذن الحالي.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<BranchBloc>()),
            BlocProvider.value(value: context.read<PhotoPermissionBloc>()),
          ],
          child: _CreateRequestBottomSheet(
            supervisorDelegate: widget.supervisorDelegate,
            parentContext: context,
          ),
        );
      },
    );
  }
}

class _CreateRequestBottomSheet extends StatefulWidget {
  final Delegate supervisorDelegate;
  final BuildContext parentContext;

  const _CreateRequestBottomSheet({
    required this.supervisorDelegate,
    required this.parentContext,
  });

  @override
  State<_CreateRequestBottomSheet> createState() => _CreateRequestBottomSheetState();
}

class _CreateRequestBottomSheetState extends State<_CreateRequestBottomSheet> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _endDate = DateTime.now().add(const Duration(days: 30));
    context.read<BranchBloc>().add(BranchLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    return Material(
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
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

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                // كارت توضيح مدة الإذن تلقائياً لمدة شهر
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
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
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'شهر واحد (30 يوم)',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
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
                            'تاريخ البداية (اليوم): ${DateFormat('yyyy-MM-dd').format(_startDate)}',
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
                            'تاريخ النهاية تلقائياً: ${DateFormat('yyyy-MM-dd').format(_endDate)}',
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // كارت توضيح سريان الإذن على جميع الفروع تلقائياً
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
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
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'جميع الفروع (${branches.length})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'سيتم تطبيق إذن التصوير تلقائياً على كافة فروع الشركة بدون استثناء.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (isLoadingBranches || branches.isEmpty)
                      ? null
                      : () {
                          widget.parentContext.read<PhotoPermissionBloc>().add(
                                RequestPermissionRequested(
                                  organizationUID: widget.supervisorDelegate.organizationUID,
                                  companyUID: widget.supervisorDelegate.companyUID,
                                  companyName: widget.supervisorDelegate.companyName,
                                  companyCode: null,
                                  branchIds: branches.map((b) => b.id).toList(),
                                  branchNames: branches.map((b) => b.branchName).toList(),
                                  startDate: _startDate,
                                  endDate: _endDate,
                                  requestedBy: widget.supervisorDelegate.uid,
                                ),
                              );
                          Navigator.pop(context);
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'إرسال الطلب للاعتماد (شامل كل الفروع)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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

class ApproverNameText extends StatefulWidget {
  final String approvedBy;
  final TextStyle? style;
  final String prefix;
  final String? organizationUID;
  final String? companyUID;
  final String? currentUserUid;
  final String? currentUserName;

  const ApproverNameText({
    super.key,
    required this.approvedBy,
    this.style,
    this.prefix = '',
    this.organizationUID,
    this.companyUID,
    this.currentUserUid,
    this.currentUserName,
  });

  static final Map<String, String> _userNameCache = {};

  @override
  State<ApproverNameText> createState() => _ApproverNameTextState();
}

class _ApproverNameTextState extends State<ApproverNameText> {
  String? _resolvedName;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _resolveName();
  }

  @override
  void didUpdateWidget(covariant ApproverNameText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.approvedBy != widget.approvedBy) {
      _resolveName();
    }
  }

  bool _isLikelyUid(String text) {
    final trimmed = text.trim();
    return !trimmed.contains(' ') &&
        RegExp(r'^[a-zA-Z0-9_-]{15,45}$').hasMatch(trimmed);
  }

  Future<void> _resolveName() async {
    final text = widget.approvedBy.trim();
    if (text.isEmpty) {
      if (mounted) {
        setState(() {
          _resolvedName = '';
          _isLoading = false;
        });
      }
      return;
    }

    if (!_isLikelyUid(text)) {
      if (mounted) {
        setState(() {
          _resolvedName = text;
          _isLoading = false;
        });
      }
      return;
    }

    if (ApproverNameText._userNameCache.containsKey(text)) {
      if (mounted) {
        setState(() {
          _resolvedName = ApproverNameText._userNameCache[text];
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final firestore = FirebaseFirestore.instance;

      if (widget.currentUserUid != null && text == widget.currentUserUid) {
        if (widget.currentUserName != null && widget.currentUserName!.isNotEmpty) {
          ApproverNameText._userNameCache[text] = widget.currentUserName!;
          if (mounted) {
            setState(() {
              _resolvedName = widget.currentUserName!;
              _isLoading = false;
            });
          }
          return;
        }
      }

      if (widget.organizationUID != null) {
        // Try specific company first if provided
        if (widget.companyUID != null) {
          final delegateDoc = await firestore
              .collection('organizations')
              .doc(widget.organizationUID)
              .collection('companies')
              .doc(widget.companyUID)
              .collection('delegates')
              .doc(text)
              .get();

          if (delegateDoc.exists && delegateDoc.data() != null) {
            final data = delegateDoc.data()!;
            final nameResult = _extractName(data);
            if (nameResult.isNotEmpty) {
              _setResolvedName(text, nameResult);
              return;
            }
          }
        }
        
        // Search all companies in organization
        final companies = await firestore
            .collection('organizations')
            .doc(widget.organizationUID)
            .collection('companies')
            .get();
            
        for (var company in companies.docs) {
          if (widget.companyUID != null && company.id == widget.companyUID) continue; // Already checked
          
          final delegateDoc = await firestore
              .collection('organizations')
              .doc(widget.organizationUID)
              .collection('companies')
              .doc(company.id)
              .collection('delegates')
              .doc(text)
              .get();
              
          if (delegateDoc.exists && delegateDoc.data() != null) {
            final data = delegateDoc.data()!;
            final nameResult = _extractName(data);
            if (nameResult.isNotEmpty) {
              _setResolvedName(text, nameResult);
              return;
            }
          }
        }
      }      final userDoc = await firestore.collection('users').doc(text).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        final nameResult = _extractName(data);

        if (nameResult.isNotEmpty) {
          _setResolvedName(text, nameResult);
          return;
        }
      }

      final groupQuery = await firestore
          .collectionGroup('users')
          .where('uid', isEqualTo: text)
          .limit(1)
          .get();

      if (groupQuery.docs.isNotEmpty) {
        final data = groupQuery.docs.first.data();
        final nameResult = _extractName(data);
        if (nameResult.isNotEmpty) {
          _setResolvedName(text, nameResult);
          return;
        }
      }

      final delegatesQuery = await firestore
          .collectionGroup('delegates')
          .where('uid', isEqualTo: text)
          .limit(1)
          .get();

      if (delegatesQuery.docs.isNotEmpty) {
        final data = delegatesQuery.docs.first.data();
        final nameResult = _extractName(data);
        if (nameResult.isNotEmpty) {
          _setResolvedName(text, nameResult);
          return;
        }
      }
    } catch (e) {
      debugPrint('Error resolving name: $e');
    }

    ApproverNameText._userNameCache[text] = text;
    if (mounted) {
      setState(() {
        _resolvedName = text;
        _isLoading = false;
      });
    }
  }

  String _extractName(Map<String, dynamic> data) {
    final fullName = data['fullName']?.toString() ?? '';
    final displayName = data['displayName']?.toString() ?? '';
    final firstName = data['firstName']?.toString() ?? '';
    final lastName = data['lastName']?.toString() ?? '';
    final name = data['name']?.toString() ?? '';

    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (displayName.trim().isNotEmpty) return displayName.trim();
    final combined = '$firstName $lastName'.trim();
    if (combined.isNotEmpty) return combined;
    if (name.trim().isNotEmpty) return name.trim();
    return '';
  }

  void _setResolvedName(String text, String nameResult) {
    ApproverNameText._userNameCache[text] = nameResult;
    if (mounted) {
      setState(() {
        _resolvedName = nameResult;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Text(
        '${widget.prefix}...',
        style: widget.style,
      );
    }

    final displayName = _resolvedName ?? widget.approvedBy;
    return Text(
      '${widget.prefix}$displayName',
      style: widget.style,
    );
  }
}
