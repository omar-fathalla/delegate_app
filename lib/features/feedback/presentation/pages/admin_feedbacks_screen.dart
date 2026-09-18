import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_state.dart';
import 'package:intl/intl.dart';

/// صفحة لوحة التحكم للـ Super Admin لعرض وإدارة جميع المقترحات
class AdminFeedbacksScreen extends StatefulWidget {
  const AdminFeedbacksScreen({super.key});

  @override
  State<AdminFeedbacksScreen> createState() => _AdminFeedbacksScreenState();
}

class _AdminFeedbacksScreenState extends State<AdminFeedbacksScreen> {
  FeedbackType? _selectedTypeFilter;
  FeedbackStatus? _selectedStatusFilter;

  @override
  void initState() {
    super.initState();
    context.read<AdminFeedbackBloc>().add(const LoadAllFeedbacksEvent());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'إدارة المقترحات' : 'Manage Feedbacks'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showFilterDialog(context, isArabic),
          ),
        ],
      ),
      body: BlocBuilder<AdminFeedbackBloc, AdminFeedbackState>(
        builder: (context, state) {
          if (state is AdminFeedbackLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AdminFeedbackError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      context.read<AdminFeedbackBloc>().add(
                        const LoadAllFeedbacksEvent(),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is AdminFeedbacksLoaded) {
            var feedbacks = state.feedbacks;

            // تطبيق الفلاتر
            if (_selectedTypeFilter != null) {
              feedbacks = feedbacks
                  .where((f) => f.type == _selectedTypeFilter)
                  .toList();
            }
            if (_selectedStatusFilter != null) {
              feedbacks = feedbacks
                  .where((f) => f.status == _selectedStatusFilter)
                  .toList();
            }

            if (feedbacks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.feedback_rounded,
                      size: 64,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isArabic ? 'لا توجد مقترحات' : 'No feedbacks available',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                context.read<AdminFeedbackBloc>().add(
                  const LoadAllFeedbacksEvent(),
                );
              },
              child: Column(
                children: [
                  // إحصائيات سريعة
                  _buildStatistics(state.feedbacks, theme, isArabic),

                  // قائمة المقترحات
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: feedbacks.length,
                      itemBuilder: (context, index) {
                        final feedback = feedbacks[index];
                        return _AdminFeedbackCard(
                          feedback: feedback,
                          isArabic: isArabic,
                          onTap: () =>
                              _showFeedbackDetails(context, feedback, isArabic),
                          onDelete: () => _showDeleteConfirmationDialog(
                            context,
                            feedback,
                            isArabic,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildStatistics(
    List<FeedbackEntity> feedbacks,
    ThemeData theme,
    bool isArabic,
  ) {
    final pending = feedbacks
        .where((f) => f.status == FeedbackStatus.pending)
        .length;
    final reviewed = feedbacks
        .where((f) => f.status == FeedbackStatus.reviewed)
        .length;
    final inProgress = feedbacks
        .where((f) => f.status == FeedbackStatus.inProgress)
        .length;
    final resolved = feedbacks
        .where((f) => f.status == FeedbackStatus.resolved)
        .length;
    final rejected = feedbacks
        .where((f) => f.status == FeedbackStatus.rejected)
        .length;

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatItem(
              isArabic ? 'الإجمالي' : 'Total',
              feedbacks.length.toString(),
              theme.colorScheme.primary,
            ),
            const SizedBox(width: 20),
            _buildStatItem(
              isArabic ? 'معلق' : 'Pending',
              pending.toString(),
              theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 20),
            _buildStatItem(
              isArabic ? 'مراجَع' : 'Reviewed',
              reviewed.toString(),
              theme.colorScheme.secondary,
            ),
            const SizedBox(width: 20),
            _buildStatItem(
              isArabic ? 'قيد التنفيذ' : 'In Progress',
              inProgress.toString(),
              theme.colorScheme.primary,
            ),
            const SizedBox(width: 20),
            _buildStatItem(
              isArabic ? 'تم الحل' : 'Resolved',
              resolved.toString(),
              theme.colorScheme.outline,
            ),
            const SizedBox(width: 20),
            _buildStatItem(
              isArabic ? 'مرفوض' : 'Rejected',
              rejected.toString(),
              theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
        ),
      ],
    );
  }

  void _showFilterDialog(BuildContext context, bool isArabic) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isArabic ? 'تصفية المقترحات' : 'Filter Feedbacks'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'النوع:' : 'Type:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text(isArabic ? 'الكل' : 'All'),
                  selected: _selectedTypeFilter == null,
                  onSelected: (selected) {
                    setState(() => _selectedTypeFilter = null);
                    Navigator.pop(dialogContext);
                  },
                ),
                ...FeedbackType.values.map((type) {
                  return FilterChip(
                    label: Text(type.getLabel(isArabic)),
                    selected: _selectedTypeFilter == type,
                    onSelected: (selected) {
                      setState(() => _selectedTypeFilter = type);
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              isArabic ? 'الحالة:' : 'Status:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text(isArabic ? 'الكل' : 'All'),
                  selected: _selectedStatusFilter == null,
                  onSelected: (selected) {
                    setState(() => _selectedStatusFilter = null);
                    Navigator.pop(dialogContext);
                  },
                ),
                ...FeedbackStatus.values.map((status) {
                  return FilterChip(
                    label: Text(status.getLabel(isArabic)),
                    selected: _selectedStatusFilter == status,
                    onSelected: (selected) {
                      setState(() => _selectedStatusFilter = status);
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedTypeFilter = null;
                _selectedStatusFilter = null;
              });
              Navigator.pop(dialogContext);
            },
            child: Text(isArabic ? 'إعادة تعيين' : 'Reset'),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDetails(
    BuildContext context,
    FeedbackEntity feedback,
    bool isArabic,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<AdminFeedbackBloc>(),
        child: _FeedbackDetailsSheet(
          feedback: feedback,
          isArabic: isArabic,
          onDelete: () => _showDeleteConfirmationDialog(
            context,
            feedback,
            isArabic,
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmationDialog(
    BuildContext context,
    FeedbackEntity feedback,
    bool isArabic,
  ) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Text(
              isArabic ? 'حذف المقترح' : 'Delete Feedback',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic
                  ? 'هل أنت متأكد من رغبتك في حذف هذا المقترح نهائياً؟'
                  : 'Are you sure you want to delete this feedback?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${feedback.type.getLabel(isArabic)} - ${feedback.userName}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    feedback.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<AdminFeedbackBloc>().add(
                    DeleteFeedbackEvent(feedback.id ?? ''),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isArabic
                        ? 'تم حذف المقترح بنجاح'
                        : 'Feedback deleted successfully',
                  ),
                  backgroundColor: theme.colorScheme.error,
                ),
              );
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(isArabic ? 'تأكيد الحذف' : 'Delete'),
          ),
        ],
      ),
    );
  }
}

class _AdminFeedbackCard extends StatelessWidget {
  final FeedbackEntity feedback;
  final bool isArabic;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _AdminFeedbackCard({
    required this.feedback,
    required this.isArabic,
    required this.onTap,
    this.onDelete,
  });

  (Color bg, Color fg) _getStatusColors(ColorScheme colorScheme, FeedbackStatus status) {
    switch (status) {
      case FeedbackStatus.pending:
        return (colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer);
      case FeedbackStatus.reviewed:
        return (colorScheme.secondaryContainer, colorScheme.onSecondaryContainer);
      case FeedbackStatus.inProgress:
        return (colorScheme.primaryContainer, colorScheme.onPrimaryContainer);
      case FeedbackStatus.resolved:
        return (colorScheme.surfaceContainerHighest, colorScheme.primary);
      case FeedbackStatus.rejected:
        return (colorScheme.errorContainer, colorScheme.onErrorContainer);
    }
  }

  IconData _getTypeIcon(FeedbackType type) {
    switch (type) {
      case FeedbackType.featureRequest:
        return Icons.lightbulb_rounded;
      case FeedbackType.bugReport:
        return Icons.bug_report_rounded;
      case FeedbackType.generalQuestion:
        return Icons.help_rounded;
      case FeedbackType.improvement:
        return Icons.star_rounded;
      case FeedbackType.other:
        return Icons.chat_bubble_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy - HH:mm');
    final (statusBg, statusFg) = _getStatusColors(theme.colorScheme, feedback.status);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getTypeIcon(feedback.type),
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feedback.type.getLabel(isArabic),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          feedback.userName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      feedback.status.getLabel(isArabic),
                      style: TextStyle(
                        color: statusFg,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                      tooltip: isArabic ? 'حذف المقترح' : 'Delete Feedback',
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                feedback.content,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dateFormat.format(feedback.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (feedback.screenshotUrl != null) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.image_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackDetailsSheet extends StatefulWidget {
  final FeedbackEntity feedback;
  final bool isArabic;
  final VoidCallback? onDelete;

  const _FeedbackDetailsSheet({
    required this.feedback,
    required this.isArabic,
    this.onDelete,
  });

  @override
  State<_FeedbackDetailsSheet> createState() => _FeedbackDetailsSheetState();
}

class _FeedbackDetailsSheetState extends State<_FeedbackDetailsSheet> {
  late FeedbackStatus _selectedStatus;
  final _responseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.feedback.status;
    _responseController.text = widget.feedback.adminResponse ?? '';
  }

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy - HH:mm');

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // معلومات المستخدم
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              widget.feedback.userName[0].toUpperCase(),
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.feedback.userName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  widget.feedback.userEmail,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // النوع والتاريخ
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              widget.feedback.type.getLabel(widget.isArabic),
                            ),
                            avatar: Icon(
                              _getTypeIcon(widget.feedback.type),
                              size: 18,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            dateFormat.format(widget.feedback.createdAt),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // المحتوى
                      Text(
                        widget.isArabic ? 'المحتوى:' : 'Content:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.feedback.content,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // الصورة
                      if (widget.feedback.screenshotUrl != null) ...[
                        Text(
                          widget.isArabic ? 'لقطة الشاشة:' : 'Screenshot:',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            widget.feedback.screenshotUrl!,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // تغيير الحالة
                      Text(
                        widget.isArabic ? 'الحالة:' : 'Status:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: FeedbackStatus.values.map((status) {
                          return ChoiceChip(
                            label: Text(status.getLabel(widget.isArabic)),
                            selected: _selectedStatus == status,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedStatus = status);
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      // رد الإدارة
                      Text(
                        widget.isArabic ? 'رد الإدارة:' : 'Admin Response:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _responseController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: widget.isArabic
                              ? 'اكتب ردك هنا...'
                              : 'Write your response here...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // أزرار الحفظ والحذف
                      Row(
                        children: [
                          if (widget.onDelete != null) ...[
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onDelete?.call();
                              },
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: theme.colorScheme.error,
                                size: 20,
                              ),
                              label: Text(
                                widget.isArabic ? 'حذف المقترح' : 'Delete',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: theme.colorScheme.error.withValues(alpha: 0.6),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                context.read<AdminFeedbackBloc>().add(
                                  UpdateFeedbackStatusEvent(
                                    feedbackId: widget.feedback.id!,
                                    status: _selectedStatus,
                                    adminResponse:
                                        _responseController.text.trim().isEmpty
                                        ? null
                                        : _responseController.text.trim(),
                                  ),
                                );
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      widget.isArabic
                                          ? 'تم تحديث المقترح بنجاح'
                                          : 'Feedback updated successfully',
                                      style: TextStyle(
                                        color: theme.colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.save_rounded),
                              label: Text(
                                widget.isArabic ? 'حفظ التغييرات' : 'Save Changes',
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
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
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getTypeIcon(FeedbackType type) {
    switch (type) {
      case FeedbackType.featureRequest:
        return Icons.lightbulb_rounded;
      case FeedbackType.bugReport:
        return Icons.bug_report_rounded;
      case FeedbackType.generalQuestion:
        return Icons.help_rounded;
      case FeedbackType.improvement:
        return Icons.star_rounded;
      case FeedbackType.other:
        return Icons.chat_bubble_rounded;
    }
  }
}
