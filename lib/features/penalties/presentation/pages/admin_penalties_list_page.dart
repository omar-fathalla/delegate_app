import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'admin_create_penalty_page.dart';

class AdminPenaltiesListPage extends StatefulWidget {
  final Delegate adminDelegate;

  const AdminPenaltiesListPage({super.key, required this.adminDelegate});

  @override
  State<AdminPenaltiesListPage> createState() => _AdminPenaltiesListPageState();
}

class _AdminPenaltiesListPageState extends State<AdminPenaltiesListPage> {
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    if (widget.adminDelegate.role == UserRole.admin) {
      context.read<PenaltyBloc>().add(LoadCompanyPenaltiesEvent(widget.adminDelegate.companyUID));
    } else {
      context.read<PenaltyBloc>().add(const LoadAllPenaltiesEvent());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'سجل المخالفات والغرامات',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: widget.adminDelegate.role == UserRole.admin
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final res = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: context.read<PenaltyBloc>(),
                      child: AdminCreatePenaltyPage(
                        adminDelegate: widget.adminDelegate,
                      ),
                    ),
                  ),
                );
                if (res == true) {
                  _loadData();
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('تسجيل غرامة جديدة'),
            ),
      body: BlocBuilder<PenaltyBloc, PenaltyState>(
        builder: (context, state) {
          if (state is PenaltyLoadingState) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is PenaltyErrorState) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 54, color: colorScheme.error),
                  const SizedBox(height: 12),
                  Text(state.message, style: TextStyle(color: colorScheme.error)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }

          if (state is PenaltyLoadedState) {
            final list = state.penalties;

            if (list.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_off_outlined,
                      size: 64,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد غرامات أو مخالفات مسجلة بعد',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final p = list[index];
                return _AdminPenaltyCard(
                  penalty: p,
                  isReadOnly: widget.adminDelegate.role == UserRole.admin,
                  onStatusChanged: (newStatus) {
                    context.read<PenaltyBloc>().add(
                          UpdatePenaltyStatusEvent(
                            penaltyId: p.penaltyId,
                            status: newStatus,
                          ),
                        );
                    _loadData();
                  },
                );
              },
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _AdminPenaltyCard extends StatefulWidget {
  final PenaltyEntity penalty;
  final bool isReadOnly;
  final ValueChanged<PenaltyStatus> onStatusChanged;

  const _AdminPenaltyCard({
    required this.penalty,
    required this.isReadOnly,
    required this.onStatusChanged,
  });

  @override
  State<_AdminPenaltyCard> createState() => _AdminPenaltyCardState();
}

class _AdminPenaltyCardState extends State<_AdminPenaltyCard> {
  bool _isExpanded = false;

  Color _getStatusColor(PenaltyStatus status) {
    switch (status) {
      case PenaltyStatus.issued:
        return Colors.orange.shade700;
      case PenaltyStatus.acknowledged:
        return Colors.blue.shade700;
      case PenaltyStatus.deducted:
        return Colors.red.shade700;
      case PenaltyStatus.disputed:
        return Colors.purple.shade700;
      case PenaltyStatus.cancelled:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _getStatusColor(widget.penalty.status);
    final dateStr = DateFormat('yyyy/MM/dd HH:mm').format(widget.penalty.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _isExpanded
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row (Compact mode)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      widget.penalty.status.displayName,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.penalty.companyName.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.penalty.companyName,
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  Text(
                    widget.penalty.fineAmount.toStringAsFixed(2),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Title and Category row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.penalty.title,
                      maxLines: _isExpanded ? null : 1,
                      overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.penalty.category.displayName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              // Expanded Section (Shows on Tap)
              if (_isExpanded) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                if (widget.penalty.incidentDescription.isNotEmpty) ...[
                  Text(
                    'تفاصيل المخالفة:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.penalty.incidentDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'بواسطة: ${widget.penalty.createdByName}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.calendar_today_rounded,
                        size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      dateStr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (!widget.isReadOnly)
                      PopupMenuButton<PenaltyStatus>(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: widget.onStatusChanged,
                        itemBuilder: (context) => PenaltyStatus.values.map((st) {
                          return PopupMenuItem(
                            value: st,
                            child: Text(st.displayName),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: statusColor.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'تغيير الحالة (${widget.penalty.status.displayName})',
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down_rounded,
                                  size: 16, color: statusColor),
                            ],
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (widget.penalty.evidenceFiles.isNotEmpty)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          final file = widget.penalty.evidenceFiles.first;
                          launchUrl(Uri.parse(file.fileUrl),
                              mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.attach_file_rounded, size: 16),
                        label: Text(
                          'المستندات (${widget.penalty.evidenceFiles.length})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
