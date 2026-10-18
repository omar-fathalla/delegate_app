import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/photo_permission.dart';

class SuperAdminPermissionsReportScreen extends StatefulWidget {
  final Delegate delegate;

  const SuperAdminPermissionsReportScreen({super.key, required this.delegate});

  @override
  State<SuperAdminPermissionsReportScreen> createState() =>
      _SuperAdminPermissionsReportScreenState();
}

class _SuperAdminPermissionsReportScreenState
    extends State<SuperAdminPermissionsReportScreen> {
  final Map<String, int?> _companyCodes = {};
  final Set<String> _fetchingCompanyUIDs = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    context.read<PhotoPermissionBloc>().add(
          const LoadPermissionsRequested(
            organizationUID: '',
            companyUID: '',
          ),
        );
  }

  Future<void> _fetchCompanyCodes(List<PhotoPermission> permissions) async {
    final toFetch = <PhotoPermission>[];
    for (final p in permissions) {
      if (p.companyCode != null) {
        _companyCodes[p.companyUID] = p.companyCode;
        continue;
      }
      if (p.companyUID.isNotEmpty &&
          !_companyCodes.containsKey(p.companyUID) &&
          !_fetchingCompanyUIDs.contains(p.companyUID)) {
        _fetchingCompanyUIDs.add(p.companyUID);
        toFetch.add(p);
      }
    }

    if (toFetch.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    await Future.wait(
      toFetch.map((p) async {
        try {
          final compDoc = await firestore
              .collection('organizations')
              .doc(p.organizationUID)
              .collection('companies')
              .doc(p.companyUID)
              .get();
          final data = compDoc.data();
          final rawCode = data?['code'] ?? data?['companyCodeInOrg'] ?? data?['companyCode'];
          _companyCodes[p.companyUID] =
              rawCode != null ? int.tryParse(rawCode.toString()) : null;
        } catch (_) {
          _companyCodes[p.companyUID] = null;
        } finally {
          _fetchingCompanyUIDs.remove(p.companyUID);
        }
      }),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _exportToCSV(List<PhotoPermission> activePermissions) async {
    try {
      // UTF-8 BOM to make Arabic characters load correctly in Excel
      final csvHeader = '\uFEFFاسم الشركة,كود الشركة,قيمة الاشتراك الشهري\n';
      final csvRows = activePermissions.map((p) {
        final name = p.companyName.replaceAll(',', ' ');
        final code = _companyCodes[p.companyUID]?.toString() ?? p.companyCode?.toString() ?? '-';
        return '$name,$code,500';
      }).join('\n');

      final csvContent = '$csvHeader$csvRows';

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/photo_permissions_billing.csv');
      await file.writeAsString(csvContent);

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'تقرير فواتير أذونات التصوير للشركات',
        );
      }
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل في تصدير التقرير، يرجى المحاولة لاحقاً.',
              style: TextStyle(color: colorScheme.onError),
            ),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        scrolledUnderElevation: 2.0,
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        title: const Text(
          'تقرير أذونات التصوير المالي',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      body: BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
        builder: (context, state) {
          if (state is PhotoPermissionLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is PhotoPermissionError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }

          if (state is PhotoPermissionsLoaded) {
            // Filter by organization UID (if not global super admin) and approved status
            final filtered = state.permissions.where((p) {
              final matchesOrg = widget.delegate.organizationUID.isEmpty ||
                  p.organizationUID == widget.delegate.organizationUID;
              return matchesOrg && p.status.toLowerCase() == 'approved';
            }).toList();

            // Group by company UID to make billing per-company unique
            final Map<String, PhotoPermission> uniqueCompanies = {};
            for (var perm in filtered) {
              if (!uniqueCompanies.containsKey(perm.companyUID)) {
                uniqueCompanies[perm.companyUID] = perm;
              }
            }
            final activePermissions = uniqueCompanies.values.toList();
            _fetchCompanyCodes(activePermissions);

            if (activePermissions.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.analytics_rounded,
                      size: 64,
                      color: colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لا توجد شركات لديها أذونات تصوير نشطة حالياً.',
                      style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            }

            final totalBilling = activePermissions.length * 500;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Cards Row
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'الشركات المفعّلة',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${activePermissions.length}',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          color: colorScheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'إجمالي الخصم',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$totalBilling',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Table Card
                  Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          color: colorScheme.surfaceContainerHighest,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'تفاصيل الأذونات النشطة',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton.filledTonal(
                                onPressed: () => _exportToCSV(activePermissions),
                                icon: const Icon(Icons.file_download_rounded),
                                tooltip: 'تصدير Excel',
                              ),
                            ],
                          ),
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(
                                label: Text(
                                  'اسم الشركة',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'كود الشركة',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'قيمة الإذن شهرياً',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                            rows: activePermissions.map((p) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(p.companyName)),
                                  DataCell(
                                    Text(
                                      _companyCodes[p.companyUID]?.toString() ?? p.companyCode?.toString() ?? '-',
                                      style: const TextStyle(fontFamily: 'monospace'),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '500',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
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
}
