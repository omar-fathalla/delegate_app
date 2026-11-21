import 'package:delegate_app/features/tasks/data/services/task_image_storage.dart';
import 'package:delegate_app/features/tasks/presentation/widgets/task_image_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_state.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:intl/intl.dart' hide TextDirection;

class CreateTaskScreen extends StatefulWidget {
  final Delegate adminDelegate;

  const CreateTaskScreen({super.key, required this.adminDelegate});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  TaskPriority _selectedPriority = TaskPriority.medium;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String _selectedAssignedTo = 'all';
  String _selectedAssignedToName = '';
  List<String> _images = [];
  bool _imageUploading = false;
  bool _createSubmitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.adminDelegate.role == UserRole.organizationAdmin) {
      _selectedAssignedTo = 'all_branch_marketing';
      _selectedAssignedToName = 'جميع مسؤولين تسويق الفروع';
    } else if (widget.adminDelegate.role == UserRole.marketingPromotion) {
      _selectedAssignedTo = 'all_branch_marketing';
      _selectedAssignedToName = 'جميع مسؤولين تسويق الفروع';
    }
  }

  @override
  void dispose() {
    // Abandoning the create form must not leave an unreferenced upload.
    if (!_createSubmitted) {
      for (final path in _images) {
        if (path.isNotEmpty) TaskImageStorage().deleteQuietly(path);
      }
    }
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return BlocProvider(
      create: (context) => di.sl<CreateTaskBloc>(),
      child: BlocListener<CreateTaskBloc, CreateTaskState>(
        listener: (context, state) {
          if (state is CreateTaskSuccess) {
            _createSubmitted = true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.taskCreatedSuccessfully)),
            );
            Navigator.pop(context);
          } else if (state is CreateTaskError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: Builder(
          builder: (context) {
            // Trigger initial load
            if (context.read<CreateTaskBloc>().state is CreateTaskInitial &&
                context.read<CreateTaskBloc>().state.delegates == null) {
              context.read<CreateTaskBloc>().add(
                LoadDelegatesRequested(
                  organizationId: widget.adminDelegate.organizationUID,
                  companyId: widget.adminDelegate.companyUID,
                ),
              );
            }

            return Scaffold(
              backgroundColor: theme.colorScheme.surfaceContainerLowest,
              appBar: AppBar(
                backgroundColor: theme.colorScheme.surfaceContainer,
                elevation: 0,
                scrolledUnderElevation: 2.0,
                shape: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                centerTitle: true,
                title: Text(
                  l10n.createTask,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: BlocBuilder<CreateTaskBloc, CreateTaskState>(
                    builder: (context, state) {
                      if (state is LoadingDelegates) {
                        return const LinearProgressIndicator();
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionHeader(theme, l10n.taskDetails),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.taskTitle,
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          prefixIcon: const Icon(Icons.title_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.errorFieldRequired;
                          }
                          return null;
                        },
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: l10n.taskDescription,
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 50),
                            child: Icon(Icons.description_rounded),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        maxLines: 4,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.errorFieldRequired;
                          }
                          return null;
                        },
                        keyboardType: TextInputType.multiline,
                      ),
                      const SizedBox(height: 16),
                      TaskImagePickerList(
                        organizationId: widget.adminDelegate.organizationUID,
                        companyId: widget.adminDelegate.companyUID,
                        onChanged: (paths) => setState(() => _images = paths),
                        onUploadingChanged: (v) =>
                            setState(() => _imageUploading = v),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader(theme, l10n.taskPriority),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: TaskPriority.values.map((p) {
                          final isSelected = _selectedPriority == p;
                          final color = _getPriorityColor(p);
                          return ChoiceChip(
                            avatar: isSelected
                                ? null
                                : _getPriorityIcon(p, color: color),
                            label: Text(_getPriorityName(l10n, p)),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedPriority = p);
                              }
                            },
                            showCheckmark: true,
                            selectedColor: color.withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected ? color : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader(theme, l10n.taskSchedule),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => _selectDate(context),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.calendar_month_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.taskDueDate,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag()).format(_selectedDate),
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.edit_calendar_rounded,
                                color: theme.colorScheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader(theme, l10n.assignTo),
                      const SizedBox(height: 12),
                      BlocBuilder<CreateTaskBloc, CreateTaskState>(
                        builder: (context, state) {
                          final allDelegates = (state.delegates ?? [])
                              .cast<Delegate>();

                          final isOrgAdmin = widget.adminDelegate.role ==
                                  UserRole.organizationAdmin || 
                              widget.adminDelegate.role ==
                                  UserRole.marketingPromotion;

                          return InkWell(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => _TaskAssigneeSelectionBottomSheet(
                                  currentSelectedId: _selectedAssignedTo,
                                  allDelegates: allDelegates,
                                  userRole: widget.adminDelegate.role,
                                  onSelect: (id, name) {
                                    setState(() {
                                      _selectedAssignedTo = id;
                                      _selectedAssignedToName = name;
                                    });
                                  },
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _selectedAssignedTo == 'all_branch_marketing'
                                          ? Icons.campaign_rounded
                                          : _selectedAssignedTo ==
                                                  'all_marketing_promotion'
                                              ? Icons.photo_library_rounded
                                              : _selectedAssignedTo == 'all'
                                                  ? Icons.groups_rounded
                                                  : Icons.person_pin_rounded,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isOrgAdmin
                                              ? 'جهة التعيين (موظفي التسويق / القطاع)'
                                              : l10n.selectDelegate,
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                color: theme.colorScheme.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _selectedAssignedToName.isNotEmpty
                                              ? _selectedAssignedToName
                                              : (isOrgAdmin
                                                  ? 'اختر الموظف أو القطاع'
                                                  : l10n.selectDelegate),
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'اختر / تغيير',
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.swap_vert_rounded,
                                          size: 18,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 48),
                      BlocBuilder<CreateTaskBloc, CreateTaskState>(
                        builder: (context, state) {
                          return FilledButton.icon(
                            onPressed:
                                state is CreateTaskLoading || _imageUploading
                                ? null
                                : () {
                                    if (_formKey.currentState!.validate()) {
                                      context.read<CreateTaskBloc>().add(
                                        CreateTaskSubmitted(
                                          organizationId: widget
                                              .adminDelegate
                                              .organizationUID,
                                          title: _titleController.text,
                                          description:
                                              _descriptionController.text,
                                          priority: _selectedPriority,
                                          dueDate: _selectedDate,
                                          assignedTo: _selectedAssignedTo,
                                          assignedToName:
                                              _selectedAssignedToName.isEmpty
                                              ? l10n.allDelegates
                                              : _selectedAssignedToName,
                                          companyId:
                                              widget.adminDelegate.companyUID,
                                          createdBy: widget.adminDelegate.uid,
                                          createdByName:
                                              '${widget.adminDelegate.firstName} ${widget.adminDelegate.lastName}',
                                          imageUrl: null,
                                          imagePath: _images.isEmpty
                                              ? null
                                              : _images.first,
                                          imagePaths: _images,
                                        ),
                                      );
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 64),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                            ),
                            icon: state is CreateTaskLoading
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_rounded,
                                    size: 28,
                                  ),
                            label: Text(
                              l10n.createTask,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Icon _getPriorityIcon(TaskPriority priority, {Color? color}) {
    switch (priority) {
      case TaskPriority.high:
        return Icon(Icons.priority_high_rounded, color: color, size: 20);
      case TaskPriority.medium:
        return Icon(Icons.low_priority_rounded, color: color, size: 20);
      case TaskPriority.low:
        return Icon(Icons.arrow_downward_rounded, color: color, size: 20);
    }
  }

  String _getPriorityName(AppLocalizations l10n, TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return l10n.high;
      case TaskPriority.medium:
        return l10n.medium;
      case TaskPriority.low:
        return l10n.low;
    }
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return Colors.red.shade700;
      case TaskPriority.medium:
        return Colors.orange.shade700;
      case TaskPriority.low:
        return Colors.green.shade700;
    }
  }
}

class _AssigneeItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isSector;
  final UserRole? role;

  _AssigneeItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isSector = false,
    this.role,
  });
}

class _TaskAssigneeSelectionBottomSheet extends StatefulWidget {
  final String currentSelectedId;
  final List<Delegate> allDelegates;
  final UserRole userRole;
  final Function(String id, String name) onSelect;

  const _TaskAssigneeSelectionBottomSheet({
    required this.currentSelectedId,
    required this.allDelegates,
    required this.userRole,
    required this.onSelect,
  });

  @override
  State<_TaskAssigneeSelectionBottomSheet> createState() =>
      _TaskAssigneeSelectionBottomSheetState();
}

class _TaskAssigneeSelectionBottomSheetState
    extends State<_TaskAssigneeSelectionBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilterChip = 'all'; // 'all', 'sectors', 'branch_marketing', 'promotion_marketing', 'delegates'
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOrgAdmin = widget.userRole == UserRole.organizationAdmin || widget.userRole == UserRole.marketingPromotion;
    final isSuperAdmin = widget.userRole == UserRole.superAdmin;

    // 1. Build master list of options
    final List<_AssigneeItem> options = [];

    // Sectors
    if (!isOrgAdmin) {
      options.add(_AssigneeItem(
        id: 'all',
        title: 'جميع المناديب',
        subtitle: 'إسناد المهمة لكافة مناديب الشركة',
        icon: Icons.groups_rounded,
        color: Colors.blue.shade700,
        isSector: true,
      ));
    }

    if (isSuperAdmin || isOrgAdmin) {
      options.add(_AssigneeItem(
        id: 'all_branch_marketing',
        title: 'قطاع تسويق الفروع',
        subtitle: 'جميع موظفي مسؤولي تسويق الفروع (Branch Marketing)',
        icon: Icons.campaign_rounded,
        color: Colors.amber.shade800,
        isSector: true,
      ));
      options.add(_AssigneeItem(
        id: 'all_marketing_promotion',
        title: 'قطاع تسويق العروض',
        subtitle: 'جميع موظفي مسؤولي تسويق العروض (Marketing Promotion)',
        icon: Icons.photo_library_rounded,
        color: Colors.purple.shade700,
        isSector: true,
      ));
    }

    // Individual Employees / Delegates
    for (final d in widget.allDelegates) {
      if (isOrgAdmin &&
          (d.role != UserRole.marketing &&
              d.role != UserRole.marketingPromotion)) {
        continue; // Exclude field delegates for org admin
      }

      final name = d.fullName.isNotEmpty
          ? d.fullName
          : '${d.firstName} ${d.lastName}';

      String subtitleText = 'مندوب ميداني';
      IconData iconData = Icons.person_pin_rounded;
      Color roleColor = colorScheme.primary;

      if (d.role == UserRole.marketing) {
        subtitleText = 'موظف تسويق الفروع';
        iconData = Icons.campaign_rounded;
        roleColor = colorScheme.secondary;
      } else if (d.role == UserRole.marketingPromotion) {
        subtitleText = 'موظف تسويق العروض';
        iconData = Icons.photo_library_rounded;
        roleColor = colorScheme.tertiary;
      }

      options.add(_AssigneeItem(
        id: d.uid,
        title: name,
        subtitle: subtitleText,
        icon: iconData,
        color: roleColor,
        isSector: false,
        role: d.role,
      ));
    }

    // 2. Filter by Chip Category
    List<_AssigneeItem> filtered = options.where((item) {
      if (_selectedFilterChip == 'sectors') {
        return item.isSector;
      } else if (_selectedFilterChip == 'branch_marketing') {
        return item.id == 'all_branch_marketing' ||
            item.role == UserRole.marketing;
      } else if (_selectedFilterChip == 'promotion_marketing') {
        return item.id == 'all_marketing_promotion' ||
            item.role == UserRole.marketingPromotion;
      } else if (_selectedFilterChip == 'delegates') {
        return item.id == 'all' || item.role == UserRole.delegate;
      }
      return true; // 'all'
    }).toList();

    // 3. Filter by Search Query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered
          .where((item) =>
              item.title.toLowerCase().contains(q) ||
              item.subtitle.toLowerCase().contains(q))
          .toList();
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),

          // Title & Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.person_search_rounded,
                    color: colorScheme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOrgAdmin
                            ? 'تعيين إلى (موظفي التسويق والقطاعات)'
                            : 'اختر جهة تعيين المهمة',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'استخدم الفلاتر أو حقل البحث لاختيار الشخص أو القطاع',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search Field (آلية البحث)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'ابحث باسم الموظف أو القطاع...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Filter Chips Row (آلية الفلترة)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildFilterChip('all', 'الكل (${options.length})', theme),
                const SizedBox(width: 8),
                _buildFilterChip('sectors', 'القطاعات', theme),
                const SizedBox(width: 8),
                _buildFilterChip('branch_marketing', 'تسويق الفروع', theme),
                const SizedBox(width: 8),
                _buildFilterChip('promotion_marketing', 'تسويق العروض', theme),
                if (!isOrgAdmin) ...[
                  const SizedBox(width: 8),
                  _buildFilterChip('delegates', 'المناديب الميدانيين', theme),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),

          // Options List (آلية الاختيار)
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد نتائج تطابق البحث أو الفلتر',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isSelected = item.id == widget.currentSelectedId;

                      return Card(
                        elevation: isSelected ? 3 : 0.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        color: isSelected
                            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                            : colorScheme.surface,
                        child: ListTile(
                          onTap: () {
                            widget.onSelect(item.id, item.title);
                            Navigator.pop(context);
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: item.color.withValues(alpha: 0.15),
                            child: Icon(
                              item.icon,
                              color: item.color,
                              size: 22,
                            ),
                          ),
                          title: Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            item.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: colorScheme.primary,
                                  size: 24,
                                )
                              : Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  color: colorScheme.outline,
                                  size: 22,
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, ThemeData theme) {
    final isSelected = _selectedFilterChip == key;
    final colorScheme = theme.colorScheme;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
        ),
      ),
      selected: isSelected,
      selectedColor: colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      showCheckmark: false,
      onSelected: (val) {
        if (val) setState(() => _selectedFilterChip = key);
      },
    );
  }
}
