import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

class HRDelegatesTab extends StatefulWidget {
  final Delegate hrDelegate;

  const HRDelegatesTab({super.key, required this.hrDelegate});

  @override
  State<HRDelegatesTab> createState() => _HRDelegatesTabState();
}

class _HRDelegatesTabState extends State<HRDelegatesTab> {
  final TextEditingController _searchController = TextEditingController();
  DelegateStatus? _selectedStatus;
  late AdminDelegatesBloc _delegatesBloc;

  @override
  void initState() {
    super.initState();
    _delegatesBloc = di.sl<AdminDelegatesBloc>();
    _loadDelegates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _delegatesBloc.close();
    super.dispose();
  }

  void _loadDelegates() {
    AdminDelegatesBloc.clearCache();
    _delegatesBloc.add(
      LoadCompanyDelegates(
        organizationUID: widget.hrDelegate.organizationUID,
        companyUID: widget.hrDelegate.companyUID,
      ),
    );
  }

  void _callPhone(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openWhatsApp(String phone) async {
    if (phone.isEmpty) return;
    var cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '20${cleanPhone.substring(1)}';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocProvider.value(
      value: _delegatesBloc,
      child: Column(
        children: [
          // ── Search & Filter Bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                SearchBar(
                  controller: _searchController,
                  hintText: 'بحث بالاسم، رقم الهاتف، أو الرقم القومي...',
                  elevation: WidgetStateProperty.all(0),
                  backgroundColor: WidgetStateProperty.all(
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  ),
                  leading: const Icon(Icons.search_rounded, size: 20),
                  trailing: _searchController.text.isNotEmpty
                      ? [
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          ),
                        ]
                      : null,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('جميع المناديب'),
                      selected: _selectedStatus == null,
                      onSelected: (val) {
                        if (val) setState(() => _selectedStatus = null);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.circle,
                          size: 10, color: Color(0xFF2E7D32)),
                      label: const Text('نشط'),
                      selected: _selectedStatus == DelegateStatus.active,
                      onSelected: (val) {
                        setState(() {
                          _selectedStatus =
                              val ? DelegateStatus.active : null;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.circle,
                          size: 10, color: Color(0xFFC62828)),
                      label: const Text('متوقف'),
                      selected: _selectedStatus == DelegateStatus.suspended,
                      onSelected: (val) {
                        setState(() {
                          _selectedStatus =
                              val ? DelegateStatus.suspended : null;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Delegates List ──
          Expanded(
            child: BlocBuilder<AdminDelegatesBloc, AdminDelegatesState>(
              builder: (context, state) {
                if (state is AdminDelegatesLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is AdminDelegatesError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 48, color: colorScheme.error),
                        const SizedBox(height: 12),
                        Text(state.message,
                            style: TextStyle(color: colorScheme.error)),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _loadDelegates,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                } else if (state is AdminDelegatesLoaded) {
                  final query = _searchController.text.trim().toLowerCase();
                  final filtered = state.delegates.where((d) {
                    if (query.isNotEmpty) {
                      final matchesName =
                          d.fullName.toLowerCase().contains(query);
                      final matchesPhone = d.phoneNumber.contains(query);
                      final matchesNat = d.nationalityID.contains(query);
                      if (!matchesName && !matchesPhone && !matchesNat) {
                        return false;
                      }
                    }
                    if (_selectedStatus != null &&
                        d.status != _selectedStatus) {
                      return false;
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline_rounded,
                              size: 56,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'لا يوجد مناديب مسجلين يطابقون شروط البحث',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => _loadDelegates(),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth > 750) {
                          return GridView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 550,
                              mainAxisExtent: 175,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              return _buildDelegateCard(
                                filtered[index],
                                theme,
                                colorScheme,
                              );
                            },
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _buildDelegateCard(
                              filtered[index],
                              theme,
                              colorScheme,
                            );
                          },
                        );
                      },
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDelegateCard(
    Delegate delegate,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isActive = delegate.status == DelegateStatus.active;
    final statusColor =
        isActive ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final statusText = isActive ? 'نشط' : 'متوقف';

    final posName = delegate.position == DelegatePosition.supervisor
        ? 'مشرف'
        : 'مندوب / مروج';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppAvatar(
                  imageUrl: delegate.personalPhotoUrl,
                  fallbackText: delegate.fullName,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delegate.fullName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        posName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (delegate.nationalityID.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.badge_outlined,
                                size: 14, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              delegate.nationalityID,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Actions Row
            Row(
              children: [
                if (delegate.phoneNumber.isNotEmpty) ...[
                  IconButton.filledTonal(
                    icon: const Icon(Icons.phone_rounded, size: 16),
                    tooltip: 'اتصال هاتف',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _callPhone(delegate.phoneNumber),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                    tooltip: 'واتساب',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openWhatsApp(delegate.phoneNumber),
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),

                // Monthly Attendance
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                  label: const Text('سجل الحضور'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceScreen(
                          delegate: delegate,
                          viewOnly: true,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),

                // View Profile
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.person_rounded, size: 16),
                  label: const Text('الملف'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          delegate: delegate,
                          showBackButton: true,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
