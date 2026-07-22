import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
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
      floatingActionButton: FloatingActionButton.extended(
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
          const SizedBox(height: 8),
          Text(
            'اضغط على الزر بالأسفل لطلب إذن جديد لشركتك.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
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
                    Text(
                      permission.companyName,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (permission.companyCode != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'كود الشركة: ${permission.companyCode}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
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
                if (isApproved)
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
            if (isApproved) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'متابعة المناديب وتقارير الصور:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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
  final List<Branch> _selectedBranches = [];
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _endDate = DateTime.now().add(const Duration(days: 30));
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
              const SizedBox(height: 20),
              // Branch select title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'اختر الفروع المرادة:',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (branches.isNotEmpty)
                    Row(
                      children: [
                        const Text('تحديد الكل', style: TextStyle(fontSize: 13)),
                        Checkbox(
                          value: _selectAll,
                          onChanged: (val) {
                            setState(() {
                              _selectAll = val ?? false;
                              _selectedBranches.clear();
                              if (_selectAll) {
                                _selectedBranches.addAll(branches);
                              }
                            });
                          },
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (state is BranchLoading)
                const Center(child: CircularProgressIndicator())
              else if (branches.isEmpty)
                const Center(child: Text('لا توجد فروع مسجلة بالمنظمة.'))
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: branches.length,
                    itemBuilder: (context, index) {
                      final branch = branches[index];
                      final isSelected = _selectedBranches.contains(branch);

                      return CheckboxListTile(
                        title: Text(branch.branchName),
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedBranches.add(branch);
                            } else {
                              _selectedBranches.remove(branch);
                              _selectAll = false;
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _selectedBranches.isEmpty
                    ? null
                    : () {
                        widget.parentContext.read<PhotoPermissionBloc>().add(
                              RequestPermissionRequested(
                                organizationUID: widget.supervisorDelegate.organizationUID,
                                companyUID: widget.supervisorDelegate.companyUID,
                                companyName: widget.supervisorDelegate.companyName,
                                companyCode: null,
                                branchIds: _selectedBranches.map((b) => b.id).toList(),
                                branchNames: _selectedBranches.map((b) => b.branchName).toList(),
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
                  'إرسال الطلب للاعتماد',
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
