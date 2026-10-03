import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

enum HRDelegatesViewMode { table, cards }

class HRDelegatesTab extends StatefulWidget {
  final Delegate hrDelegate;

  const HRDelegatesTab({super.key, required this.hrDelegate});

  @override
  State<HRDelegatesTab> createState() => _HRDelegatesTabState();
}

class _HRDelegatesTabState extends State<HRDelegatesTab> {
  final TextEditingController _searchController = TextEditingController();
  DelegateStatus? _selectedStatus;
  HRDelegatesViewMode _viewMode = HRDelegatesViewMode.table;
  late AdminDelegatesBloc _delegatesBloc;

  @override
  void initState() {
    super.initState();
    _viewMode = HRDelegatesViewMode.table;
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

  void _copyNationalId(String nationalId) {
    if (nationalId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: nationalId));
    AppSnackBar.showSuccess(context, 'تم نسخ الرقم القومي بنجاح');
  }

  void _copyPhoneNumber(String phone) {
    if (phone.isEmpty) return;
    Clipboard.setData(ClipboardData(text: phone));
    AppSnackBar.showSuccess(context, 'تم نسخ رقم الهاتف بنجاح');
  }

  void _openProfile(Delegate delegate, {int initialTabIndex = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => di.sl<ProfileBloc>(),
          child: ProfileScreen(
            delegate: delegate,
            showBackButton: true,
            initialTabIndex: initialTabIndex,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocProvider.value(
      value: _delegatesBloc,
      child: Column(
        children: [
          // ── Search & Filter Toolbar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            child: BlocBuilder<AdminDelegatesBloc, AdminDelegatesState>(
              builder: (context, state) {
                int total = 0;
                int activeCount = 0;
                int suspendedCount = 0;
                if (state is AdminDelegatesLoaded) {
                  total = state.delegates.length;
                  activeCount = state.delegates
                      .where((d) => d.status == DelegateStatus.active)
                      .length;
                  suspendedCount = state.delegates
                      .where((d) => d.status == DelegateStatus.suspended)
                      .length;
                }

                final searchBar = SearchBar(
                  controller: _searchController,
                  hintText: 'بحث بالاسم، رقم الهاتف، أو الرقم القومي...',
                  elevation: const WidgetStatePropertyAll(0),
                  constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  backgroundColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh,
                  ),
                  leading: Icon(Icons.search_rounded, size: 19, color: colorScheme.primary),
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
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onChanged: (_) => setState(() {}),
                );

                final statusButtonGroup = TashilConnectedButtonGroup<DelegateStatus?>(
                  height: 44,
                  selectedValue: _selectedStatus,
                  items: [
                    TashilConnectedButtonItem<DelegateStatus?>(
                      value: null,
                      label: total > 0 ? 'جميع المناديب ($total)' : 'جميع المناديب',
                      icon: Icons.people_alt_rounded,
                    ),
                    TashilConnectedButtonItem<DelegateStatus?>(
                      value: DelegateStatus.active,
                      label: activeCount > 0 ? 'نشط ($activeCount)' : 'نشط',
                      icon: Icons.check_circle_outline_rounded,
                      activeColor: const Color(0xFF2E7D32),
                    ),
                    TashilConnectedButtonItem<DelegateStatus?>(
                      value: DelegateStatus.suspended,
                      label: suspendedCount > 0 ? 'متوقف ($suspendedCount)' : 'متوقف',
                      icon: Icons.pause_circle_outline_rounded,
                      activeColor: const Color(0xFFC62828),
                    ),
                  ],
                  onSelected: (val) {
                    setState(() => _selectedStatus = val);
                  },
                );

                final viewModeButtonGroup = TashilConnectedButtonGroup<HRDelegatesViewMode>(
                  height: 44,
                  selectedValue: _viewMode,
                  items: const [
                    TashilConnectedButtonItem<HRDelegatesViewMode>(
                      value: HRDelegatesViewMode.table,
                      label: 'جدول',
                      icon: Icons.table_chart_rounded,
                    ),
                    TashilConnectedButtonItem<HRDelegatesViewMode>(
                      value: HRDelegatesViewMode.cards,
                      label: 'بطاقات',
                      icon: Icons.grid_view_rounded,
                    ),
                  ],
                  onSelected: (val) {
                    setState(() => _viewMode = val);
                  },
                );

                final refreshButton = IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    minimumSize: const Size(44, 44),
                    maximumSize: const Size(44, 44),
                  ),
                  tooltip: 'تحديث القائمة',
                  onPressed: _loadDelegates,
                  icon: const Icon(Icons.sync_rounded, size: 20),
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktopWide = constraints.maxWidth >= 960;

                    if (isDesktopWide) {
                      return Row(
                        children: [
                          Expanded(child: searchBar),
                          const SizedBox(width: 10),
                          statusButtonGroup,
                          const SizedBox(width: 10),
                          viewModeButtonGroup,
                          const SizedBox(width: 10),
                          refreshButton,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: searchBar),
                            const SizedBox(width: 8),
                            viewModeButtonGroup,
                            const SizedBox(width: 8),
                            refreshButton,
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: statusButtonGroup,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ── Delegates List / Table ──
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
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(state.message, style: TextStyle(color: colorScheme.error)),
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
                      final matchesName = d.fullName.toLowerCase().contains(query);
                      final matchesPhone = d.phoneNumber.contains(query);
                      final matchesNat = d.nationalityID.contains(query);
                      if (!matchesName && !matchesPhone && !matchesNat) {
                        return false;
                      }
                    }
                    if (_selectedStatus != null && d.status != _selectedStatus) {
                      return false;
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 56,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
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
                    child: _viewMode == HRDelegatesViewMode.table
                        ? _buildDelegatesTable(filtered, theme, colorScheme)
                        : _buildCardsGrid(filtered, theme, colorScheme),
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

  /// جدول بيانات المناديب الاحترافي (العرض الافتراضي المطلوب)
  Widget _buildDelegatesTable(
    List<Delegate> delegates,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    const minWidth = 1140.0;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width =
                constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    // Table Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Center(
                              child: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Expanded(
                            flex: 22,
                            child: Text('المندوب / المروج', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            flex: 16,
                            child: Text('الرقم القومي', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            flex: 15,
                            child: Text('رقم الهاتف', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            flex: 15,
                            child: Text('المدينة / المحافظة', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            flex: 10,
                            child: Center(
                              child: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Expanded(
                            flex: 28,
                            child: Center(
                              child: Text('الإجراءات والملف', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Table Rows
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: delegates.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final delegate = delegates[index];
                        final isActive = delegate.status == DelegateStatus.active;
                        final statusColor =
                            isActive ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
                        final statusText = isActive ? 'نشط' : 'متوقف';

                        final posName = delegate.position == DelegatePosition.supervisor
                            ? 'مشرف'
                            : 'مندوب / مروج';

                        return InkWell(
                          onTap: () => _openProfile(delegate),
                          hoverColor: colorScheme.primaryContainer.withValues(alpha: 0.12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            color: index.isEven
                                ? colorScheme.surface
                                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
                            child: Row(
                              children: [
                                // # Index
                                Expanded(
                                  flex: 4,
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),

                                // Delegate Info (Avatar + Name + Role)
                                Expanded(
                                  flex: 22,
                                  child: Row(
                                    children: [
                                      AppAvatar(
                                        imageUrl: delegate.personalPhotoUrl,
                                        fallbackText: delegate.fullName,
                                        radius: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              delegate.fullName,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              posName,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // National ID
                                Expanded(
                                  flex: 16,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.badge_outlined,
                                        size: 15,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: SelectableText(
                                          delegate.nationalityID.isNotEmpty
                                              ? delegate.nationalityID
                                              : '—',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                            letterSpacing: 0.5,
                                          ),
                                          textAlign: TextAlign.start,
                                        ),
                                      ),
                                      if (delegate.nationalityID.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.copy_rounded, size: 14),
                                          tooltip: 'نسخ الرقم القومي',
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                          onPressed: () => _copyNationalId(delegate.nationalityID),
                                        ),
                                    ],
                                  ),
                                ),

                                // Phone Number
                                Expanded(
                                  flex: 15,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.phone_iphone_rounded,
                                        size: 15,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: SelectableText(
                                          delegate.phoneNumber.isNotEmpty
                                              ? delegate.phoneNumber
                                              : '—',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                            letterSpacing: 0.3,
                                          ),
                                          textAlign: TextAlign.start,
                                        ),
                                      ),
                                      if (delegate.phoneNumber.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.copy_rounded, size: 14),
                                          tooltip: 'نسخ رقم الهاتف',
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                          onPressed: () => _copyPhoneNumber(delegate.phoneNumber),
                                        ),
                                    ],
                                  ),
                                ),

                                // City / Location
                                Expanded(
                                  flex: 15,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_outlined,
                                        size: 15,
                                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          delegate.city.isNotEmpty
                                              ? delegate.city
                                              : (delegate.companyName.isNotEmpty
                                                  ? delegate.companyName
                                                  : '—'),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Status Badge
                                Expanded(
                                  flex: 10,
                                  child: Center(
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border:
                                            Border.all(color: statusColor.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.circle, size: 7, color: statusColor),
                                          const SizedBox(width: 5),
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
                                  ),
                                ),

                                // Actions (Call + WhatsApp + Attendance + Profile)
                                Expanded(
                                  flex: 28,
                                  child: Center(
                                    child: _buildTableActionsButtonGroup(delegate, colorScheme),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// عرض شبكة البطاقات (كخيار تبديل إضافي)
  Widget _buildCardsGrid(
    List<Delegate> filtered,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 750) {
          return GridView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _buildDelegateCard(
              filtered[index],
              theme,
              colorScheme,
            );
          },
        );
      },
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
                const Spacer(),
                _buildTableActionsButtonGroup(delegate, colorScheme),
              ],
            ),
          ],
        ),
      ),
    );
  }


  /// أزرار الإجراءات والتواصل والملف كـ Button Group موحدة وفق M3
  Widget _buildTableActionsButtonGroup(Delegate delegate, ColorScheme colorScheme) {
    final hasPhone = delegate.phoneNumber.trim().isNotEmpty;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // زر الاتصال الهاتفي (Google Icon)
          if (hasPhone) ...[
            Material(
              color: Colors.transparent,
              child: Tooltip(
                message: 'اتصال هاتفي (${delegate.phoneNumber})',
                child: InkWell(
                  onTap: () => _callPhone(delegate.phoneNumber),
                  hoverColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Icon(
                        Icons.phone_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            // زر الواتساب (Google Icon)
            Material(
              color: Colors.transparent,
              child: Tooltip(
                message: 'مراسلة عبر واتساب (${delegate.phoneNumber})',
                child: InkWell(
                  onTap: () => _openWhatsApp(delegate.phoneNumber),
                  hoverColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: const Center(
                      child: Icon(
                        Icons.chat_bubble_rounded,
                        size: 14,
                        color: Color(0xFF1EBE5D),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ],
          // زر سجل الحضور
          Material(
            color: Colors.transparent,
            child: Tooltip(
              message: 'سجل الحضور والانصراف',
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HRDelegateAttendanceDetailScreen(
                        delegate: delegate,
                        hrDelegate: widget.hrDelegate,
                      ),
                    ),
                  );
                },
                hoverColor: colorScheme.primary.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.how_to_reg_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'سجل الحضور',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // فاصل دقيق بين الزرين
          Container(
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          // زر الملف الشخصي والبيانات الورقية
          Material(
            color: Colors.transparent,
            child: Tooltip(
              message: 'الملف والوثائق الرسمية',
              child: InkWell(
                onTap: () => _openProfile(delegate),
                hoverColor: colorScheme.primary.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_shared_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'الملف',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
