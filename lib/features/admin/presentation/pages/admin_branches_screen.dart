import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import '../../data/models/branch_model.dart';
import '../bloc/branch_bloc.dart';
import 'add_branch_screen.dart';
import 'organization_branches_screen.dart';

class AdminBranchesScreen extends StatelessWidget {
  final bool showAppBar;
  const AdminBranchesScreen({super.key, this.showAppBar = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<BranchBloc>()..add(BranchLoadRequested()),
      child: _AdminBranchesView(showAppBar: showAppBar),
    );
  }
}

class _AdminBranchesView extends StatefulWidget {
  final bool showAppBar;
  const _AdminBranchesView({this.showAppBar = false});

  @override
  State<_AdminBranchesView> createState() => _AdminBranchesViewState();
}

class _AdminBranchesViewState extends State<_AdminBranchesView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> _organizations = [];
  bool _isLoadingOrgs = true;
  StreamSubscription<QuerySnapshot>? _orgsSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToOrganizations();
  }

  void _subscribeToOrganizations() {
    _orgsSubscription = FirebaseFirestore.instance
        .collection('organizations')
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final orgs = snapshot.docs.map((doc) {
              final data = doc.data();
              final name = data['name'] as String? ??
                  data['title'] as String? ??
                  data['orgName'] as String? ??
                  doc.id;
              return {
                'uid': doc.id,
                'name': name,
              };
            }).toList();

            orgs.sort(
              (a, b) =>
                  (a['name'] as String).compareTo(b['name'] as String),
            );

            setState(() {
              _organizations = orgs;
              _isLoadingOrgs = false;
            });
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _isLoadingOrgs = false;
              });
            }
          },
        );
  }

  @override
  void dispose() {
    _orgsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(
                l10n.branches,
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final bloc = context.read<BranchBloc>();
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AddBranchScreen(showAppBar: true),
            ),
          );
          if (mounted) {
            bloc.add(BranchLoadRequested());
          }
        },
        icon: const Icon(Icons.add_business_rounded),
        label: Text(
          'إضافة فرع',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocBuilder<BranchBloc, BranchState>(
        builder: (context, state) {
          if ((state is BranchLoading || state is BranchInitial) &&
              _isLoadingOrgs) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is BranchError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
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

          final allBranches = (state is BranchLoaded)
              ? state.branches.cast<BranchModel>()
              : <BranchModel>[];

          // Map org UID to branch list
          final Map<String, List<BranchModel>> orgBranchesMap = {};
          final List<BranchModel> unassignedBranches = [];

          final knownOrgUIDs = _organizations.map((o) => o['uid'] as String).toSet();
          final knownOrgNames = _organizations.map((o) => (o['name'] as String).trim().toLowerCase()).toSet();

          for (final b in allBranches) {
            if (b.organizationUID != null &&
                knownOrgUIDs.contains(b.organizationUID)) {
              orgBranchesMap.putIfAbsent(b.organizationUID!, () => []).add(b);
            } else if (b.organizationName != null &&
                knownOrgNames.contains(b.organizationName!.trim().toLowerCase())) {
              final matchingOrg = _organizations.firstWhere(
                (o) =>
                    (o['name'] as String).trim().toLowerCase() ==
                    b.organizationName!.trim().toLowerCase(),
              );
              orgBranchesMap.putIfAbsent(matchingOrg['uid'] as String, () => []).add(b);
            } else {
              unassignedBranches.add(b);
            }
          }

          // Filter organizations based on search query
          final filteredOrgs = _organizations.where((org) {
            if (_searchQuery.isEmpty) return true;
            final name = (org['name'] as String).toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

          final bool showUnassignedCard = unassignedBranches.isNotEmpty &&
              (_searchQuery.isEmpty ||
                  'فروع عامة غير مصنفة'.contains(_searchQuery.toLowerCase()));

          return RefreshIndicator(
            onRefresh: () async {
              context.read<BranchBloc>().add(BranchLoadRequested());
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Top Summary Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search Bar
                        TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() => _searchQuery = val.trim());
                          },
                          decoration: InputDecoration(
                            hintText: 'ابحث عن منظمة...',
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
                            fillColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
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
                        const SizedBox(height: 16),

                        // Stats Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primaryContainer,
                                colorScheme.primaryContainer.withValues(alpha: 0.7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.corporate_fare_rounded,
                                        color: colorScheme.primary,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_organizations.length}',
                                          style: GoogleFonts.cairo(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onPrimaryContainer,
                                            height: 1.1,
                                          ),
                                        ),
                                        Text(
                                          'منظمة مسجلة',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.onPrimaryContainer
                                                .withValues(alpha: 0.8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.storefront_rounded,
                                          color: colorScheme.primary,
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${allBranches.length}',
                                            style: GoogleFonts.cairo(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onPrimaryContainer,
                                              height: 1.1,
                                            ),
                                          ),
                                          Text(
                                            'إجمالي الفروع',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colorScheme.onPrimaryContainer
                                                  .withValues(alpha: 0.8),
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
                        ),
                        const SizedBox(height: 16),

                        // Section Title
                        Text(
                          'اختر المنظمة لعرض فروعها',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Organizations List
                if (filteredOrgs.isEmpty && !showUnassignedCard)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.corporate_fare_rounded,
                            size: 64,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'لا توجد منظمة بهذا الاسم'
                                : 'لا توجد منظمات مسجلة بعد',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // If unassigned card is shown, place it at index 0 or at the end
                          if (showUnassignedCard && index == filteredOrgs.length) {
                            return _buildUnassignedCard(
                              context,
                              colorScheme,
                              unassignedBranches,
                            );
                          }

                          final org = filteredOrgs[index];
                          final orgUID = org['uid'] as String;
                          final orgName = org['name'] as String;
                          final branchCount =
                              (orgBranchesMap[orgUID]?.length ?? 0);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              elevation: 0,
                              color: colorScheme.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  final bloc = context.read<BranchBloc>();
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BlocProvider.value(
                                        value: bloc,
                                        child: OrganizationBranchesScreen(
                                          organizationUID: orgUID,
                                          organizationName: orgName,
                                        ),
                                      ),
                                    ),
                                  );
                                  if (mounted) {
                                    bloc.add(BranchLoadRequested());
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          Icons.corporate_fare_rounded,
                                          color: colorScheme.onPrimaryContainer,
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              orgName,
                                              style: GoogleFonts.cairo(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurface,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: branchCount > 0
                                                    ? colorScheme.secondaryContainer
                                                    : colorScheme
                                                        .surfaceContainerHighest,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                branchCount > 0
                                                    ? '$branchCount ${branchCount == 1 ? 'فرع' : (branchCount == 2 ? 'فرعان' : (branchCount <= 10 ? 'فروع' : 'فرع'))}'
                                                    : 'لا توجد فروع بعد',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: branchCount > 0
                                                      ? colorScheme
                                                          .onSecondaryContainer
                                                      : colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 16,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: filteredOrgs.length + (showUnassignedCard ? 1 : 0),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildUnassignedCard(
    BuildContext context,
    ColorScheme colorScheme,
    List<BranchModel> unassignedBranches,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final bloc = context.read<BranchBloc>();
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: bloc,
                  child: const OrganizationBranchesScreen(
                    organizationUID: '',
                    organizationName: 'فروع عامة / غير مصنفة',
                    isUnassigned: true,
                  ),
                ),
              ),
            );
            if (mounted) {
              bloc.add(BranchLoadRequested());
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.store_mall_directory_outlined,
                    color: colorScheme.onTertiaryContainer,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'فروع عامة (غير معينة لمنظمة)',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${unassignedBranches.length} فرع سابق',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
