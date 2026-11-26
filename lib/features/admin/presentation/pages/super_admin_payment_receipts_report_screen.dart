import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class SuperAdminPaymentReceiptsReportScreen extends StatefulWidget {
  final Delegate delegate;

  const SuperAdminPaymentReceiptsReportScreen({super.key, required this.delegate});

  @override
  State<SuperAdminPaymentReceiptsReportScreen> createState() =>
      _SuperAdminPaymentReceiptsReportScreenState();
}

class _SuperAdminPaymentReceiptsReportScreenState
    extends State<SuperAdminPaymentReceiptsReportScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _companyReceipts = [];
  final Map<String, int?> _companyCodes = {};
  int _totalReceiptsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Fetch all delegates using collectionGroup
      final delegatesSnapshot =
          await firestore.collectionGroup('delegates').get();

      // 2. Filter delegates by organization if the Super Admin belongs to a specific one
      final filteredDelegates = delegatesSnapshot.docs.where((doc) {
        final pathParts = doc.reference.path.split('/');
        final orgUid = pathParts.length > 1 ? pathParts[1] : '';
        
        if (widget.delegate.organizationUID.isNotEmpty &&
            orgUid != widget.delegate.organizationUID) {
          return false;
        }
        return true;
      }).toList();

      // 3. Aggregate uploads by companyUID
      // Map structure: companyUID -> { 'companyName': String, 'orgUID': String, 'count': int }
      final Map<String, Map<String, dynamic>> aggregation = {};
      int totalCount = 0;

      for (var doc in filteredDelegates) {
        final pathParts = doc.reference.path.split('/');
        if (pathParts.length < 4) continue;
        
        final orgUID = pathParts[1];
        final companyUID = pathParts[3];
        
        final data = doc.data();
        final companyName = data['companyName']?.toString() ?? 'بدون اسم';

        if (companyUID.isEmpty) continue;

        // Count how many electronic payment receipts this delegate has uploaded
        final documentsList = data['documents'] as List? ?? [];
        int delegateReceiptsCount = 0;

        for (var docItem in documentsList) {
          if (docItem is Map<String, dynamic>) {
            final key = docItem['documentKey']?.toString().toLowerCase() ?? '';
            final url = docItem['documentURL']?.toString() ?? '';
            
            // Matches 'electronicPaymentReceipt', 'electronic_payment_receipt', etc.
            if ((key == 'electronicpaymentreceipt' || 
                 key == 'electronic_payment_receipt' || 
                 key == 'electronic_receipt' || 
                 key == 'electronicreceipt') && url.isNotEmpty) {
              delegateReceiptsCount++;
            }
          }
        }

        if (delegateReceiptsCount > 0) {
          totalCount += delegateReceiptsCount;
          if (aggregation.containsKey(companyUID)) {
            aggregation[companyUID]!['count'] =
                (aggregation[companyUID]!['count'] as int) + delegateReceiptsCount;
          } else {
            aggregation[companyUID] = {
              'companyUID': companyUID,
              'companyName': companyName,
              'organizationUID': orgUID,
              'count': delegateReceiptsCount,
            };
          }
        }
      }

      final resultsList = aggregation.values.toList();

      if (mounted) {
        setState(() {
          _companyReceipts = resultsList;
          _totalReceiptsCount = totalCount;
          _isLoading = false;
        });

        // Trigger async lookup of company codes
        _fetchCompanyCodes(resultsList);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'حدث خطأ أثناء جلب البيانات: $e';
        });
      }
    }
  }

  Future<void> _fetchCompanyCodes(List<Map<String, dynamic>> items) async {
    final firestore = FirebaseFirestore.instance;
    bool updated = false;

    for (var item in items) {
      final companyUID = item['companyUID'] as String;
      final organizationUID = item['organizationUID'] as String;

      if (!_companyCodes.containsKey(companyUID)) {
        try {
          final compDoc = await firestore
              .collection('organizations')
              .doc(organizationUID)
              .collection('companies')
              .doc(companyUID)
              .get();
          
          final data = compDoc.data();
          if (data != null && data['code'] != null) {
            _companyCodes[companyUID] = int.tryParse(data['code'].toString());
          } else {
            _companyCodes[companyUID] = null;
          }
        } catch (_) {
          _companyCodes[companyUID] = null;
        }
        updated = true;
      }
    }

    if (updated && mounted) {
      setState(() {});
    }
  }

  Future<void> _exportToCSV() async {
    if (_companyReceipts.isEmpty) return;

    try {
      // UTF-8 BOM to make Arabic characters load correctly in Excel
      final csvHeader = '\uFEFFاسم الشركة,كود الشركة,عدد الإيصالات الإلكترونية المرفوعة\n';
      final csvRows = _companyReceipts.map((item) {
        final name = (item['companyName'] as String).replaceAll(',', ' ');
        final companyUID = item['companyUID'] as String;
        final code = _companyCodes[companyUID]?.toString() ?? '-';
        final count = item['count'].toString();
        return '$name,$code,$count';
      }).join('\n');

      final csvContent = '$csvHeader$csvRows';

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/payment_receipts_report.csv');
      await file.writeAsString(csvContent);

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'تقرير فواتير وعدد إيصالات الدفع المرفوعة للشركات',
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
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            l10n.paymentReceiptsReport,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14.5,
              letterSpacing: -0.2,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _buildBody(colorScheme, theme, l10n),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, ThemeData theme, AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
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
        ),
      );
    }

    if (_companyReceipts.isEmpty) {
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
              'لا توجد إيصالات دفع مرفوعة حالياً.',
              style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary cards Row
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: l10n.companiesWithUploads,
                  value: _companyReceipts.length.toString(),
                  color: colorScheme.primaryContainer,
                  icon: Icons.business_rounded,
                  iconColor: colorScheme.onPrimaryContainer,
                  textColor: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  title: l10n.totalUploadedReceipts,
                  value: _totalReceiptsCount.toString(),
                  color: colorScheme.secondaryContainer,
                  icon: Icons.receipt_long_rounded,
                  iconColor: colorScheme.onSecondaryContainer,
                  textColor: colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Billing Data Table card
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'تفاصيل الإيصالات الإلكترونية',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _exportToCSV,
                        icon: const Icon(Icons.file_download_rounded),
                        tooltip: 'تصدير Excel',
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      const DataColumn(
                        label: Text(
                          'اسم الشركة',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const DataColumn(
                        label: Text(
                          'كود الشركة',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          l10n.uploadsCount,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    rows: _companyReceipts.map((item) {
                      final companyUID = item['companyUID'] as String;
                      final code = _companyCodes[companyUID]?.toString() ?? '-';

                      return DataRow(
                        cells: [
                          DataCell(Text(item['companyName'] as String)),
                          DataCell(
                            Text(
                              code,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                          DataCell(
                            Text(
                              item['count'].toString(),
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

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required Color iconColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, color: iconColor, size: 24),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
