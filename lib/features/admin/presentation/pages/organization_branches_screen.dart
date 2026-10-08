import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import '../../data/models/branch_model.dart';
import '../bloc/branch_bloc.dart';
import 'add_branch_screen.dart';

class OrganizationBranchesScreen extends StatefulWidget {
  final String organizationUID;
  final String organizationName;
  final bool isUnassigned;

  const OrganizationBranchesScreen({
    super.key,
    required this.organizationUID,
    required this.organizationName,
    this.isUnassigned = false,
  });

  @override
  State<OrganizationBranchesScreen> createState() =>
      _OrganizationBranchesScreenState();
}

class _OrganizationBranchesScreenState
    extends State<OrganizationBranchesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.organizationName,
              style: GoogleFonts.cairo(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'فروع المنظمة',
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final bloc = context.read<BranchBloc>();
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddBranchScreen(
                showAppBar: true,
                initialOrganizationUID:
                    widget.isUnassigned ? null : widget.organizationUID,
                initialOrganizationName:
                    widget.isUnassigned ? null : widget.organizationName,
              ),
            ),
          );
          if (mounted) {
            bloc.add(BranchLoadRequested());
          }
        },
        icon: const Icon(Icons.add_location_alt_rounded),
        label: Text(
          'إضافة فرع',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocBuilder<BranchBloc, BranchState>(
        builder: (context, state) {
          if (state is BranchLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is BranchError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () =>
                        context.read<BranchBloc>().add(BranchLoadRequested()),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          List<BranchModel> orgBranches = [];
          if (state is BranchLoaded) {
            final allBranches = state.branches.cast<BranchModel>();
            if (widget.isUnassigned) {
              orgBranches = allBranches.where((b) {
                return b.organizationUID == null ||
                    b.organizationUID!.isEmpty;
              }).toList();
            } else {
              orgBranches = allBranches.where((b) {
                return b.organizationUID == widget.organizationUID ||
                    (b.organizationName != null &&
                        b.organizationName!.trim().toLowerCase() ==
                            widget.organizationName.trim().toLowerCase());
              }).toList();
            }
          }

          final filteredBranches = orgBranches.where((branch) {
            if (_searchQuery.isEmpty) return true;
            return branch.branchName.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
          }).toList();

          return RefreshIndicator(
            onRefresh: () async =>
                context.read<BranchBloc>().add(BranchLoadRequested()),
            child: Column(
              children: [
                // Search Field
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() => _searchQuery = val.trim());
                    },
                    decoration: InputDecoration(
                      hintText: 'ابحث في فروع ${widget.organizationName}...',
                      hintStyle: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
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
                      fillColor: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // Branches Count Info
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'إجمالي الفروع: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${filteredBranches.length}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Branches List or Empty State
                Expanded(
                  child: filteredBranches.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.4,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.store_mall_directory_rounded,
                                      size: 72,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'لا توجد فروع مطابقة للبحث'
                                          : 'لا توجد فروع مسجلة لهذه المنظمة حتى الآن',
                                      style: GoogleFonts.cairo(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (_searchQuery.isEmpty) ...[
                                      const SizedBox(height: 12),
                                      FilledButton.tonalIcon(
                                        onPressed: () async {
                                          final bloc =
                                              context.read<BranchBloc>();
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => AddBranchScreen(
                                                showAppBar: true,
                                                initialOrganizationUID:
                                                    widget.isUnassigned
                                                        ? null
                                                        : widget
                                                            .organizationUID,
                                                initialOrganizationName:
                                                    widget.isUnassigned
                                                        ? null
                                                        : widget
                                                            .organizationName,
                                              ),
                                            ),
                                          );
                                          if (mounted) {
                                            bloc.add(BranchLoadRequested());
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.add_location_alt_rounded,
                                        ),
                                        label: const Text('إضافة فرع الآن'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                          itemCount: filteredBranches.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final branch = filteredBranches[index];

                            return Card(
                              elevation: 0,
                              color: colorScheme.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.storefront_rounded,
                                    color: colorScheme.onPrimaryContainer,
                                    size: 24,
                                  ),
                                ),
                                title: Text(
                                  branch.branchName,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.radar_rounded,
                                        size: 14,
                                        color: colorScheme.secondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'نطاق: ${branch.geofenceRadius.toInt()}م',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.secondary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          '${branch.latitude.toStringAsFixed(4)}, ${branch.longitude.toStringAsFixed(4)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.qr_code_2_rounded,
                                    color: colorScheme.primary,
                                    size: 22,
                                  ),
                                ),
                                onTap: () {
                                  context
                                      .push(
                                        '/admin/branch-details',
                                        extra: branch,
                                      )
                                      .then((_) {
                                        if (context.mounted) {
                                          context.read<BranchBloc>().add(
                                            BranchLoadRequested(),
                                          );
                                        }
                                      });
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
