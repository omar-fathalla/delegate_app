import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:delegate_app/features/admin/data/collection_transactions_loader.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// صفحة ومنظومة التحصيلات والفواتير الرسمية المعكوسة على الرصيد المتبقي مع الطباعة والمشاركة
class SuperAdminCollectionsScreen extends StatefulWidget {
  final Delegate delegate;

  const SuperAdminCollectionsScreen({super.key, required this.delegate});

  @override
  State<SuperAdminCollectionsScreen> createState() => _SuperAdminCollectionsScreenState();
}

class _SuperAdminCollectionsScreenState extends State<SuperAdminCollectionsScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();

  bool _isLoading = true;
  String? _errorMessage;

  // Selected Service Period (Month / Year)
  late DateTime _selectedPeriod;

  // Invoice Mode: 'remaining' (Default: صافي الرصيد المتبقي) or 'gross' (الإجمالي الكلي للشهر)
  bool _showRemainingInvoice = true;

  // Configurable Financial Rates (Default values matching official spec)
  double _receiptUnitPrice = 100.0;
  double _adCompanyUnitPrice = 20000.0;
  int _adCompanyCount = 7;
  double _eventsAnalyticsUnitPrice = 0.0;
  int _eventsAnalyticsCount = 1;
  String _eventsAnalyticsTitle = 'Events Analytics Software Subscription';
  double _settlementAmount = 0.0;
  String _settlementTitle = 'Settlement & Additional Adjustments';
  double _tashilPercentage = 70.0;
  double _marketPercentage = 30.0;
  double _accountantPercentage = 20.0;

  // Aggregated Billing Data from Delegates
  int _totalDueReceiptsCount = 0;

  // Recorded Collection Transactions across all months
  List<Map<String, dynamic>> _allCollectionTransactions = [];
  bool _filterTransactionsByCurrentMonth = false;
  int _transactionsPage = 0;
  static const int _transactionsPageSize = 12;

  List<Map<String, dynamic>> get _currentPeriodTransactions =>
      _allCollectionTransactions.where((t) => (t['periodKey'] ?? '') == _periodKey).toList();

  List<Map<String, dynamic>> get _displayedTransactions {
    if (_filterTransactionsByCurrentMonth) {
      return _currentPeriodTransactions;
    }
    return _allCollectionTransactions;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedPeriod = DateTime(now.year, now.month, 1);
    _loadSettingsAndData();
  }

  String get _periodKey =>
      '${_selectedPeriod.year}_${_selectedPeriod.month.toString().padLeft(2, '0')}';

  Future<void> _loadSettingsAndData() async {
    await _loadSavedPreferences();
    await _fetchBillingAndCollectionsData();
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _receiptUnitPrice = prefs.getDouble('billing_receipt_unit_price') ?? 100.0;
        _adCompanyUnitPrice = prefs.getDouble('billing_ad_company_unit_price') ?? 20000.0;
        _adCompanyCount = prefs.getInt('billing_ad_company_count') ?? 7;
        _eventsAnalyticsUnitPrice = prefs.getDouble('billing_events_analytics_unit_price_$_periodKey') ??
            prefs.getDouble('billing_events_analytics_unit_price') ??
            0.0;
        _eventsAnalyticsCount = prefs.getInt('billing_events_analytics_count_$_periodKey') ??
            prefs.getInt('billing_events_analytics_count') ??
            1;
        _eventsAnalyticsTitle = prefs.getString('billing_events_analytics_title_$_periodKey') ??
            prefs.getString('billing_events_analytics_title') ??
            'Events Analytics Software Subscription';
        _settlementAmount = prefs.getDouble('billing_settlement_amount_$_periodKey') ??
            prefs.getDouble('billing_settlement_amount') ??
            0.0;
        _settlementTitle = prefs.getString('billing_settlement_title_$_periodKey') ??
            prefs.getString('billing_settlement_title') ??
            'Settlement & Additional Adjustments';
        _tashilPercentage = prefs.getDouble('billing_tashil_percentage') ?? 70.0;
        _marketPercentage = prefs.getDouble('billing_market_percentage') ?? 30.0;
        _accountantPercentage = prefs.getDouble('billing_accountant_percentage') ?? 20.0;
      });
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('billing_receipt_unit_price', _receiptUnitPrice);
      await prefs.setDouble('billing_ad_company_unit_price', _adCompanyUnitPrice);
      await prefs.setInt('billing_ad_company_count', _adCompanyCount);
      await prefs.setDouble('billing_events_analytics_unit_price_$_periodKey', _eventsAnalyticsUnitPrice);
      await prefs.setDouble('billing_events_analytics_unit_price', _eventsAnalyticsUnitPrice);
      await prefs.setInt('billing_events_analytics_count_$_periodKey', _eventsAnalyticsCount);
      await prefs.setInt('billing_events_analytics_count', _eventsAnalyticsCount);
      await prefs.setString('billing_events_analytics_title_$_periodKey', _eventsAnalyticsTitle);
      await prefs.setString('billing_events_analytics_title', _eventsAnalyticsTitle);
      await prefs.setDouble('billing_settlement_amount_$_periodKey', _settlementAmount);
      await prefs.setDouble('billing_settlement_amount', _settlementAmount);
      await prefs.setString('billing_settlement_title_$_periodKey', _settlementTitle);
      await prefs.setString('billing_settlement_title', _settlementTitle);
      await prefs.setDouble('billing_tashil_percentage', _tashilPercentage);
      await prefs.setDouble('billing_market_percentage', _marketPercentage);
      await prefs.setDouble('billing_accountant_percentage', _accountantPercentage);

      // Persist to Firestore monthly_collections doc for sync across devices
      await FirebaseFirestore.instance
          .collection('monthly_collections')
          .doc(_periodKey)
          .set({
        'receiptUnitPrice': _receiptUnitPrice,
        'adCompanyUnitPrice': _adCompanyUnitPrice,
        'adCompanyCount': _adCompanyCount,
        'eventsAnalyticsUnitPrice': _eventsAnalyticsUnitPrice,
        'eventsAnalyticsCount': _eventsAnalyticsCount,
        'eventsAnalyticsTitle': _eventsAnalyticsTitle,
        'settlementAmount': _settlementAmount,
        'settlementTitle': _settlementTitle,
        'tashilPercentage': _tashilPercentage,
        'marketPercentage': _marketPercentage,
        'accountantPercentage': _accountantPercentage,
        'accountantRemainingAmount': _accountantRemainingAmount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _fetchBillingAndCollectionsData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    // Cache-First: instant load from persistent cache
    final cachedReceipts = prefs.getInt('cached_due_receipts_${widget.delegate.organizationUID}') ?? 0;
    if (cachedReceipts > 0 && mounted) {
      setState(() {
        _totalDueReceiptsCount = cachedReceipts;
        _isLoading = false;
      });
    }

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Fetch total due electronic receipts across delegates
      int totalElectronicReceipts = _totalDueReceiptsCount;
      try {
        final delegatesSnapshot = await firestore.collectionGroup('delegates').get();

        final filteredDelegates = delegatesSnapshot.docs.where((doc) {
          final pathParts = doc.reference.path.split('/');
          final orgUid = pathParts.length > 1 ? pathParts[1] : '';

          if (widget.delegate.organizationUID.isNotEmpty &&
              orgUid != widget.delegate.organizationUID) {
            return false;
          }
          return true;
        }).toList();

        int count = 0;
        for (var doc in filteredDelegates) {
          final data = doc.data();
          final documentsList = data['documents'] as List? ?? [];

          for (var docItem in documentsList) {
            if (docItem is Map<String, dynamic>) {
              final key = docItem['documentKey']?.toString().toLowerCase() ?? '';
              final url = docItem['documentURL']?.toString() ?? '';

              if ((key == 'electronicpaymentreceipt' ||
                      key == 'electronic_payment_receipt' ||
                      key == 'electronic_receipt' ||
                      key == 'electronicreceipt') &&
                  url.isNotEmpty) {
                count++;
              }
            }
          }
        }
        totalElectronicReceipts = count;
        await prefs.setInt('cached_due_receipts_${widget.delegate.organizationUID}', count);
      } catch (e) {
        debugPrint('Delegates fetch notice: $e');
      }

      // 2. Fetch monthly settings overrides from Firestore if available
      try {
        final monthDoc = await firestore.collection('monthly_collections').doc(_periodKey).get();
        if (monthDoc.exists) {
          final mData = monthDoc.data()!;
          if (mData['settlementAmount'] != null) {
            _settlementAmount = (mData['settlementAmount'] as num).toDouble();
          }
          if (mData['settlementTitle'] != null) {
            _settlementTitle = mData['settlementTitle'].toString();
          }
          if (mData['receiptUnitPrice'] != null) {
            _receiptUnitPrice = (mData['receiptUnitPrice'] as num).toDouble();
          }
          if (mData['adCompanyUnitPrice'] != null) {
            _adCompanyUnitPrice = (mData['adCompanyUnitPrice'] as num).toDouble();
          }
          if (mData['adCompanyCount'] != null) {
            _adCompanyCount = (mData['adCompanyCount'] as num).toInt();
          }
          if (mData['eventsAnalyticsUnitPrice'] != null) {
            _eventsAnalyticsUnitPrice = (mData['eventsAnalyticsUnitPrice'] as num).toDouble();
          }
          if (mData['eventsAnalyticsCount'] != null) {
            _eventsAnalyticsCount = (mData['eventsAnalyticsCount'] as num).toInt();
          }
          if (mData['eventsAnalyticsTitle'] != null) {
            _eventsAnalyticsTitle = mData['eventsAnalyticsTitle'].toString();
          }
          if (mData['tashilPercentage'] != null) {
            _tashilPercentage = (mData['tashilPercentage'] as num).toDouble();
          }
          if (mData['marketPercentage'] != null) {
            _marketPercentage = (mData['marketPercentage'] as num).toDouble();
          }
          if (mData['accountantPercentage'] != null) {
            _accountantPercentage = (mData['accountantPercentage'] as num).toDouble();
          }
        } else {
          // If this month does not have configuration yet in Firestore, inherit from the latest configured month
          final latestDocs = await firestore
              .collection('monthly_collections')
              .orderBy(FieldPath.documentId, descending: true)
              .limit(5)
              .get();

          for (final doc in latestDocs.docs) {
            if (doc.id != _periodKey && doc.data()['adCompanyCount'] != null) {
              final prevData = doc.data();
              _adCompanyCount = (prevData['adCompanyCount'] as num?)?.toInt() ?? _adCompanyCount;
              _adCompanyUnitPrice = (prevData['adCompanyUnitPrice'] as num?)?.toDouble() ?? _adCompanyUnitPrice;
              _receiptUnitPrice = (prevData['receiptUnitPrice'] as num?)?.toDouble() ?? _receiptUnitPrice;
              _eventsAnalyticsUnitPrice = (prevData['eventsAnalyticsUnitPrice'] as num?)?.toDouble() ?? _eventsAnalyticsUnitPrice;
              _eventsAnalyticsCount = (prevData['eventsAnalyticsCount'] as num?)?.toInt() ?? _eventsAnalyticsCount;
              _eventsAnalyticsTitle = prevData['eventsAnalyticsTitle']?.toString() ?? _eventsAnalyticsTitle;
              _settlementAmount = (prevData['settlementAmount'] as num?)?.toDouble() ?? _settlementAmount;
              _settlementTitle = prevData['settlementTitle']?.toString() ?? _settlementTitle;
              _tashilPercentage = (prevData['tashilPercentage'] as num?)?.toDouble() ?? _tashilPercentage;
              _marketPercentage = (prevData['marketPercentage'] as num?)?.toDouble() ?? _marketPercentage;
              _accountantPercentage = (prevData['accountantPercentage'] as num?)?.toDouble() ?? _accountantPercentage;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Month doc fetch notice: $e');
      }

      // 3. Fetch recorded collection transactions across all months
      List<Map<String, dynamic>> allTransactions = [];
      try {
        allTransactions = await loadAllCollectionTransactions(firestore);
      } catch (e) {
        debugPrint('Transactions fetch notice: $e');
      }

      if (mounted) {
        setState(() {
          _totalDueReceiptsCount = totalElectronicReceipts;
          _allCollectionTransactions = allTransactions;
          _isLoading = false;
          _errorMessage = null;
        });

        // Sync computed totals to Firestore for real-time visibility across accountant and devices
        try {
          firestore.collection('monthly_collections').doc(_periodKey).set({
            'totalDueReceiptsCount': _totalDueReceiptsCount,
            'grandTotalDue': _grandTotalDue,
            'totalCollectedAmount': _totalCollectedAmount,
            'remainingBalanceAmount': _remainingBalanceAmount,
            'accountantPercentage': _accountantPercentage,
            'accountantRemainingAmount': _accountantRemainingAmount,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_totalDueReceiptsCount == 0) {
            _errorMessage = 'An error occurred while loading collections data: $e';
          }
        });
      }
    }
  }

  // --- Financial Calculations (Cumulative across all collections) ---
  int get _totalCollectedReceiptsCount {
    int sum = 0;
    for (final t in _allCollectionTransactions) {
      sum += (t['receiptsCount'] as num? ?? 0).toInt();
    }
    return sum;
  }

  int get _totalCollectedAdCompaniesCount {
    int sum = 0;
    for (final t in _allCollectionTransactions) {
      sum += (t['adCompaniesCount'] as num? ?? 0).toInt();
    }
    return sum;
  }

  int get _totalCollectedEventsAnalyticsCount {
    int sum = 0;
    for (final t in _allCollectionTransactions) {
      sum += (t['eventsAnalyticsCount'] as num? ?? 0).toInt();
    }
    return sum;
  }

  double get _totalCollectedSettlementAmount {
    double sum = 0.0;
    for (final t in _allCollectionTransactions) {
      sum += (t['settlementAmount'] as num? ?? 0.0).toDouble();
    }
    return sum;
  }

  double get _totalCollectedAmount {
    double sum = 0.0;
    for (final t in _allCollectionTransactions) {
      sum += (t['collectedAmount'] as num? ?? 0.0).toDouble();
    }
    return sum;
  }

  // Gross Total Due (الإجمالي المستحق الكلي مع البنود الأربعة)
  double get _dueReceiptsTotalAmount => _totalDueReceiptsCount * _receiptUnitPrice;
  double get _adCompanyTotalAmount => _adCompanyCount * _adCompanyUnitPrice;
  double get _eventsAnalyticsTotalAmount => _eventsAnalyticsCount * _eventsAnalyticsUnitPrice;
  double get _grandTotalDue =>
      _dueReceiptsTotalAmount + _adCompanyTotalAmount + _eventsAnalyticsTotalAmount + _settlementAmount;

  // Net Remaining (المتبقي الفعلي بعد الخصم)
  int get _remainingReceiptsCount =>
      (_totalDueReceiptsCount - _totalCollectedReceiptsCount).clamp(0, _totalDueReceiptsCount);

  double get _remainingReceiptsAmount => _remainingReceiptsCount * _receiptUnitPrice;

  int get _remainingAdCompaniesCount =>
      (_adCompanyCount - _totalCollectedAdCompaniesCount).clamp(0, _adCompanyCount);

  double get _remainingAdCompanyAmount => _remainingAdCompaniesCount * _adCompanyUnitPrice;

  int get _remainingEventsAnalyticsCount =>
      (_eventsAnalyticsCount - _totalCollectedEventsAnalyticsCount).clamp(0, _eventsAnalyticsCount);

  double get _remainingEventsAnalyticsAmount => _remainingEventsAnalyticsCount * _eventsAnalyticsUnitPrice;

  double get _remainingSettlementAmount =>
      (_settlementAmount - _totalCollectedSettlementAmount).clamp(0.0, _settlementAmount);

  double get _remainingBalanceAmount =>
      (_remainingReceiptsAmount + _remainingAdCompanyAmount + _remainingEventsAnalyticsAmount + _remainingSettlementAmount)
          .clamp(0.0, _grandTotalDue);

  // Active Invoice Displayed Values (بناءً على اختيار المتبقي أو الإجمالي)
  int get _invoiceReceiptsQty => _showRemainingInvoice ? _remainingReceiptsCount : _totalDueReceiptsCount;
  double get _invoiceReceiptsTotal => _showRemainingInvoice ? _remainingReceiptsAmount : _dueReceiptsTotalAmount;
  int get _invoiceAdCompaniesQty => _showRemainingInvoice ? _remainingAdCompaniesCount : _adCompanyCount;
  double get _invoiceAdCompaniesTotal => _showRemainingInvoice ? _remainingAdCompanyAmount : _adCompanyTotalAmount;
  int get _invoiceEventsAnalyticsQty => _showRemainingInvoice ? _remainingEventsAnalyticsCount : _eventsAnalyticsCount;
  double get _invoiceEventsAnalyticsTotal =>
      _showRemainingInvoice ? _remainingEventsAnalyticsAmount : _eventsAnalyticsTotalAmount;
  double get _invoiceSettlementTotal => _showRemainingInvoice ? _remainingSettlementAmount : _settlementAmount;
  double get _invoiceGrandTotal => _showRemainingInvoice ? _remainingBalanceAmount : _grandTotalDue;

  // Shares of Active Invoice
  double get _invoiceTashilAmount => (_invoiceGrandTotal * _tashilPercentage) / 100.0;
  double get _invoiceMarketAmount => (_invoiceGrandTotal * _marketPercentage) / 100.0;

  // Shares of Total Due
  double get _tashilDueAmount => (_grandTotalDue * _tashilPercentage) / 100.0;
  double get _marketDueAmount => (_grandTotalDue * _marketPercentage) / 100.0;

  // Shares of Collected Amount
  double get _tashilCollectedAmount => (_totalCollectedAmount * _tashilPercentage) / 100.0;
  double get _marketCollectedAmount => (_totalCollectedAmount * _marketPercentage) / 100.0;

  // Shares of Remaining Balance
  double get _tashilRemainingAmount => (_remainingBalanceAmount * _tashilPercentage) / 100.0;
  double get _marketRemainingAmount => (_remainingBalanceAmount * _marketPercentage) / 100.0;
  double get _accountantRemainingAmount => (_remainingBalanceAmount * _accountantPercentage) / 100.0;

  double get _collectionProgressPercentage =>
      _grandTotalDue > 0 ? ((_totalCollectedAmount / _grandTotalDue) * 100.0).clamp(0.0, 100.0) : 0.0;

  String _formatCurrency(num amount) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '${formatter.format(amount)} EGP';
  }

  String _formatAmountOnly(num amount) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return formatter.format(amount);
  }

  String _numberToWordsEnglish(num number) {
    final formatter = NumberFormat('#,##0', 'en_US');
    return '${formatter.format(number.toInt())} Egyptian pounds only.';
  }

  // --- Add New Collection Entry Dialog (منظومة تسجيل التحصيل والخصم للمدخلات الأربعة) ---
  void _showAddCollectionDialog() {
    final receiptsCountController = TextEditingController();
    final receiptsAmountController = TextEditingController();
    final adCountController = TextEditingController();
    final adAmountController = TextEditingController();
    final eventsCountController = TextEditingController();
    final eventsAmountController = TextEditingController();
    final settlementAmountController = TextEditingController();
    final notesController = TextEditingController();
    String selectedPaymentMethod = 'Cash';

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final dialogColorScheme = Theme.of(ctx).colorScheme;
            final rQty = int.tryParse(receiptsCountController.text) ?? 0;
            final rAmt = double.tryParse(receiptsAmountController.text) ?? (rQty * _receiptUnitPrice);

            final aQty = int.tryParse(adCountController.text) ?? 0;
            final aAmt = double.tryParse(adAmountController.text) ?? (aQty * _adCompanyUnitPrice);

            final evQty = int.tryParse(eventsCountController.text) ?? 0;
            final evAmt = double.tryParse(eventsAmountController.text) ?? (evQty * _eventsAnalyticsUnitPrice);

            final sAmt = double.tryParse(settlementAmountController.text) ?? 0.0;

            final totalEntryAmount = (rAmt > 0 ? rAmt : (rQty * _receiptUnitPrice)) +
                (aAmt > 0 ? aAmt : (aQty * _adCompanyUnitPrice)) +
                (evAmt > 0 ? evAmt : (evQty * _eventsAnalyticsUnitPrice)) +
                sAmt;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              contentPadding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: dialogColorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_card_rounded, color: dialogColorScheme.onPrimaryContainer, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Record Collection & Deduction',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: dialogColorScheme.onSurface),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overview of Outstanding Balances
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: dialogColorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: dialogColorScheme.outlineVariant.withValues(alpha: 0.6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.account_balance_wallet_rounded, size: 14, color: dialogColorScheme.primary),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Current Outstanding Balance:',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: dialogColorScheme.primary),
                                    ),
                                  ],
                                ),
                                Text(
                                  _formatCurrency(_remainingBalanceAmount),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dialogColorScheme.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  '• Receipts: $_remainingReceiptsCount (${_formatAmountOnly(_remainingReceiptsAmount)} EGP)',
                                  style: TextStyle(fontSize: 10, color: dialogColorScheme.onSurface),
                                ),
                                Text(
                                  '• Ad Cos: $_remainingAdCompaniesCount (${_formatAmountOnly(_remainingAdCompanyAmount)} EGP)',
                                  style: TextStyle(fontSize: 10, color: dialogColorScheme.onSurface),
                                ),
                                if (_eventsAnalyticsTotalAmount > 0 || _eventsAnalyticsUnitPrice > 0)
                                  Text(
                                    '• Events Analytics: $_remainingEventsAnalyticsCount (${_formatAmountOnly(_remainingEventsAnalyticsAmount)} EGP)',
                                    style: TextStyle(fontSize: 10, color: dialogColorScheme.onSurface),
                                  ),
                                if (_settlementAmount > 0)
                                  Text(
                                    '• Settlement: ${_formatAmountOnly(_remainingSettlementAmount)} EGP',
                                    style: TextStyle(fontSize: 10, color: dialogColorScheme.onSurface),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Stream 1: Electronic Payment Receipts
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: dialogColorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: dialogColorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.receipt_long_rounded, size: 16, color: dialogColorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '1. Electronic Payment Receipts',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: dialogColorScheme.primary),
                                  ),
                                ),
                                Text(
                                  'Rem: $_remainingReceiptsCount',
                                  style: TextStyle(fontSize: 10, color: dialogColorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextField(
                                    controller: receiptsCountController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Receipts Qty',
                                      hintText: 'e.g. 385',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (val) {
                                      final count = int.tryParse(val) ?? 0;
                                      if (count > 0) {
                                        receiptsAmountController.text = (count * _receiptUnitPrice).toStringAsFixed(0);
                                      } else if (val.isEmpty) {
                                        receiptsAmountController.text = '';
                                      }
                                      setDialogState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 6,
                                  child: TextField(
                                    controller: receiptsAmountController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Amount (EGP)',
                                      hintText: 'e.g. 38500',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (_) => setDialogState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Stream 2: Advertising Company Subscription
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: dialogColorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: dialogColorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.campaign_rounded, size: 16, color: dialogColorScheme.secondary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '2. Advertising Companies Subscription',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: dialogColorScheme.secondary),
                                  ),
                                ),
                                Text(
                                  'Rem: $_remainingAdCompaniesCount',
                                  style: TextStyle(fontSize: 10, color: dialogColorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextField(
                                    controller: adCountController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Companies Qty',
                                      hintText: 'e.g. 2',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (val) {
                                      final count = int.tryParse(val) ?? 0;
                                      if (count > 0) {
                                        adAmountController.text = (count * _adCompanyUnitPrice).toStringAsFixed(0);
                                      } else if (val.isEmpty) {
                                        adAmountController.text = '';
                                      }
                                      setDialogState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 6,
                                  child: TextField(
                                    controller: adAmountController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Amount (EGP)',
                                      hintText: 'e.g. 40000',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (_) => setDialogState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Stream 3: Events Analytics Software
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: dialogColorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: dialogColorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.analytics_rounded, size: 16, color: dialogColorScheme.tertiary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '3. Events Analytics Software',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: dialogColorScheme.tertiary),
                                  ),
                                ),
                                Text(
                                  'Rem: $_remainingEventsAnalyticsCount',
                                  style: TextStyle(fontSize: 10, color: dialogColorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextField(
                                    controller: eventsCountController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Programs Qty',
                                      hintText: 'e.g. 1',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (val) {
                                      final count = int.tryParse(val) ?? 0;
                                      if (count > 0) {
                                        eventsAmountController.text = (count * _eventsAnalyticsUnitPrice).toStringAsFixed(0);
                                      } else if (val.isEmpty) {
                                        eventsAmountController.text = '';
                                      }
                                      setDialogState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 6,
                                  child: TextField(
                                    controller: eventsAmountController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Amount (EGP)',
                                      hintText: 'e.g. 15000',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onChanged: (_) => setDialogState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Stream 4: Settlement & Additional Adjustments
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: dialogColorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: dialogColorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.balance_rounded, size: 16, color: dialogColorScheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '4. Settlement & Adjustments',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: dialogColorScheme.primary),
                                  ),
                                ),
                                if (_settlementAmount > 0)
                                  Text(
                                    'Rem: ${_formatAmountOnly(_remainingSettlementAmount)}',
                                    style: TextStyle(fontSize: 10, color: dialogColorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: settlementAmountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Settlement Amount (EGP)',
                                hintText: 'e.g. 10000',
                                prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Total Deduction Summary Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: dialogColorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: dialogColorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Collection Entry:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: dialogColorScheme.onPrimaryContainer),
                            ),
                            Text(
                              _formatCurrency(totalEntryAmount),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: dialogColorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Payment Method Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: selectedPaymentMethod,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Payment Method',
                          prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                          DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                          DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                          DropdownMenuItem(value: 'Online / Card', child: Text('Online / Card')),
                          DropdownMenuItem(value: 'Deduction from Dues', child: Text('Deduction from Dues')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedPaymentMethod = val);
                          }
                        },
                      ),
                      const SizedBox(height: 10),

                      // Notes / Cheque No.
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Notes / Cheque No.',
                          hintText: 'Payment details or transaction reference...',
                          prefixIcon: const Icon(Icons.edit_note_rounded, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: dialogColorScheme.primary,
                    foregroundColor: dialogColorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final recQty = int.tryParse(receiptsCountController.text) ?? 0;
                    final recAmt = double.tryParse(receiptsAmountController.text) ?? (recQty * _receiptUnitPrice);

                    final adQty = int.tryParse(adCountController.text) ?? 0;
                    final adAmt = double.tryParse(adAmountController.text) ?? (adQty * _adCompanyUnitPrice);

                    final evQty = int.tryParse(eventsCountController.text) ?? 0;
                    final evAmt = double.tryParse(eventsAmountController.text) ?? (evQty * _eventsAnalyticsUnitPrice);

                    final setAmt = double.tryParse(settlementAmountController.text) ?? 0.0;

                    final totalAmt = (recAmt > 0 ? recAmt : (recQty * _receiptUnitPrice)) +
                        (adAmt > 0 ? adAmt : (adQty * _adCompanyUnitPrice)) +
                        (evAmt > 0 ? evAmt : (evQty * _eventsAnalyticsUnitPrice)) +
                        setAmt;

                    if (recQty <= 0 && recAmt <= 0 && adQty <= 0 && adAmt <= 0 && evQty <= 0 && evAmt <= 0 && setAmt <= 0 && totalAmt <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Please enter at least one collection quantity or amount.'),
                          backgroundColor: dialogColorScheme.error,
                        ),
                      );
                      return;
                    }

                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(ctx);

                    try {
                      final firestore = FirebaseFirestore.instance;
                      final docRef = firestore
                          .collection('monthly_collections')
                          .doc(_periodKey)
                          .collection('transactions')
                          .doc();

                      await docRef.set({
                        'id': docRef.id,
                        'receiptsCount': recQty,
                        'receiptsAmount': recAmt,
                        'adCompaniesCount': adQty,
                        'adCompaniesAmount': adAmt,
                        'eventsAnalyticsCount': evQty,
                        'eventsAnalyticsAmount': evAmt,
                        'settlementAmount': setAmt,
                        'collectedAmount': totalAmt,
                        'unitPrice': _receiptUnitPrice,
                        'adUnitPrice': _adCompanyUnitPrice,
                        'eventsAnalyticsUnitPrice': _eventsAnalyticsUnitPrice,
                        'paymentMethod': selectedPaymentMethod,
                        'notes': notesController.text.trim(),
                        'createdAt': FieldValue.serverTimestamp(),
                        'createdBy': widget.delegate.fullName,
                        'periodKey': _periodKey,
                      });

                      if (mounted) {
                        nav.pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Recorded collection of ${_formatCurrency(totalAmt)}'
                              '${recQty > 0 ? ' ($recQty receipts)' : ''}'
                              '${adQty > 0 ? ' ($adQty ad companies)' : ''}'
                              '${evQty > 0 ? ' ($evQty events analytics)' : ''}'
                              '${setAmt > 0 ? ' (settlement: ${_formatAmountOnly(setAmt)} EGP)' : ''}.',
                            ),
                          ),
                        );
                        _fetchBillingAndCollectionsData();
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Error saving collection: $e'),
                            backgroundColor: dialogColorScheme.error,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Confirm Deduction', style: TextStyle(fontSize: 12)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteCollectionTransaction(
    String docId, {
    required int receiptsCount,
    required double receiptsAmount,
    required int adCompaniesCount,
    required double adCompaniesAmount,
    required int eventsAnalyticsCount,
    required double eventsAnalyticsAmount,
    required double settlementAmount,
    required double totalAmount,
    String? transactionPeriodKey,
  }) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 22),
              const SizedBox(width: 8),
              const Text('Confirm Deletion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this invoice amounting to ${_formatCurrency(totalAmount)}?',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'The following will be restored to due balance:',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                    if (receiptsCount > 0 || receiptsAmount > 0)
                      Text('• $receiptsCount Receipts (${_formatAmountOnly(receiptsAmount)} EGP)', style: const TextStyle(fontSize: 10)),
                    if (adCompaniesCount > 0 || adCompaniesAmount > 0)
                      Text('• $adCompaniesCount Ad Companies (${_formatAmountOnly(adCompaniesAmount)} EGP)', style: const TextStyle(fontSize: 10)),
                    if (eventsAnalyticsCount > 0 || eventsAnalyticsAmount > 0)
                      Text('• $eventsAnalyticsCount Events Analytics (${_formatAmountOnly(eventsAnalyticsAmount)} EGP)', style: const TextStyle(fontSize: 10)),
                    if (settlementAmount > 0)
                      Text('• Settlement: ${_formatAmountOnly(settlementAmount)} EGP', style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final targetPeriod = (transactionPeriodKey != null && transactionPeriodKey.isNotEmpty)
            ? transactionPeriodKey
            : _periodKey;
        await FirebaseFirestore.instance
            .collection('monthly_collections')
            .doc(targetPeriod)
            .collection('transactions')
            .doc(docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invoice deleted and balances restored.'),
            ),
          );
          _fetchBillingAndCollectionsData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting invoice: $e'),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      }
    }
  }

  // --- Print Invoice (طباعة الفاتورة عبر الطابعة أو PDF) ---
  Future<void> _printInvoice() async {
    try {
      final imageBytes = await _screenshotController.capture(
        delay: const Duration(milliseconds: 100),
        pixelRatio: 3.0,
      );

      if (imageBytes == null) return;

      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      final periodStr = DateFormat('yyyy-MM').format(_selectedPeriod);
      final docName = 'Invoice_${_showRemainingInvoice ? 'Remaining' : 'Total'}_$periodStr.pdf';

      await Printing.layoutPdf(
        name: docName,
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing invoice: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // --- Share Invoice (مشاركة الفاتورة كصورة عبر الواتساب) ---
  Future<void> _shareInvoiceImage() async {
    try {
      final image = await _screenshotController.capture(
        delay: const Duration(milliseconds: 100),
        pixelRatio: 2.5,
      );

      if (image == null) return;

      final directory = await getTemporaryDirectory();
      final periodStr = DateFormat('yyyy-MM').format(_selectedPeriod);
      final fileName = 'Official_Invoice_${_showRemainingInvoice ? 'Remaining' : 'Total'}_$periodStr.png';
      final imagePath = '${directory.path}/$fileName';
      final file = File(imagePath);
      await file.writeAsBytes(image);

      final invoiceNo = '${_selectedPeriod.year}${_selectedPeriod.month}000/46';
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: 'Official Collections Invoice (${_showRemainingInvoice ? 'Net Remaining Balance' : 'Gross Total'}) - Invoice No: $invoiceNo for period: ${DateFormat('MMMM yyyy', 'en_US').format(_selectedPeriod)} - Total: ${_formatCurrency(_invoiceGrandTotal)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing invoice: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showSettingsDialog() {
    final receiptPriceController =
        TextEditingController(text: _receiptUnitPrice.toStringAsFixed(0));
    final adPriceController =
        TextEditingController(text: _adCompanyUnitPrice.toStringAsFixed(0));
    final adCountController =
        TextEditingController(text: _adCompanyCount.toString());
    final eventsPriceController =
        TextEditingController(text: _eventsAnalyticsUnitPrice.toStringAsFixed(0));
    final eventsCountController =
        TextEditingController(text: _eventsAnalyticsCount.toString());
    final eventsTitleController =
        TextEditingController(text: _eventsAnalyticsTitle);
    final settlementAmountController = TextEditingController(
        text: _settlementAmount > 0 ? _settlementAmount.toStringAsFixed(0) : '');
    final settlementTitleController =
        TextEditingController(text: _settlementTitle);
    final tashilPercController =
        TextEditingController(text: _tashilPercentage.toStringAsFixed(0));
    final marketPercController =
        TextEditingController(text: _marketPercentage.toStringAsFixed(0));
    final accountantPercController =
        TextEditingController(text: _accountantPercentage.toStringAsFixed(0));

    final settingsTheme = Theme.of(context);
    final settingsColorScheme = settingsTheme.colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Icon(Icons.tune_rounded, color: settingsColorScheme.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Pricing & Ratios Settings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: receiptPriceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Receipt Unit Price (EGP)',
                      prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: adPriceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Ad Company License Price (EGP)',
                      prefixIcon: const Icon(Icons.campaign_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: adCountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Ad Companies Count (Qty)',
                      prefixIcon: const Icon(Icons.numbers_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Events Analytics Software Field (بند برنامج تحليل الإيفنتات)
                  TextField(
                    controller: eventsPriceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Events Analytics Price (EGP)',
                      prefixIcon: const Icon(Icons.analytics_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: eventsCountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Events Analytics Count (Qty)',
                      prefixIcon: const Icon(Icons.data_usage_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: eventsTitleController,
                    decoration: InputDecoration(
                      labelText: 'Events Analytics Label (Invoice)',
                      hintText: 'Events Analytics Software Subscription',
                      prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Settlement & Other Revenue Field (خانة التسويات والإيرادات الإضافية)
                  TextField(
                    controller: settlementAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Settlement & Adjustments (EGP)',
                      hintText: 'e.g. 15000',
                      helperText: 'Additional revenue/settlement added to Grand Total',
                      prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: settlementTitleController,
                    decoration: InputDecoration(
                      labelText: 'Settlement Item Label (Invoice)',
                      hintText: 'Settlement & Additional Adjustments',
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),

                  const Text(
                    'Percentage Split (%):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tashilPercController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Tashil (%)',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onChanged: (v) {
                            final val = double.tryParse(v) ?? 70.0;
                            if (val <= 100) {
                              marketPercController.text = (100.0 - val).toStringAsFixed(0);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: marketPercController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Fathalla (%)',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  const Text(
                    'Accountant Share from Remaining (%):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: accountantPercController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Accountant Share (% / نسبة إدارة الحسابات من المتبقي)',
                      prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final rPrice = double.tryParse(receiptPriceController.text) ?? 100.0;
                  final aPrice = double.tryParse(adPriceController.text) ?? 20000.0;
                  final aCount = int.tryParse(adCountController.text) ?? 7;
                  final evPrice = double.tryParse(eventsPriceController.text) ?? 20000.0;
                  final evCount = int.tryParse(eventsCountController.text) ?? 1;
                  final evTitle = eventsTitleController.text.trim().isNotEmpty
                      ? eventsTitleController.text.trim()
                      : 'Events Analytics Software Subscription';
                  final sAmount = double.tryParse(settlementAmountController.text) ?? 0.0;
                  final sTitle = settlementTitleController.text.trim().isNotEmpty
                      ? settlementTitleController.text.trim()
                      : 'Settlement & Additional Adjustments';
                  final tPerc = double.tryParse(tashilPercController.text) ?? 70.0;
                  final mPerc = double.tryParse(marketPercController.text) ?? 30.0;
                  final accPerc = double.tryParse(accountantPercController.text) ?? 20.0;

                  setState(() {
                    _receiptUnitPrice = rPrice;
                    _adCompanyUnitPrice = aPrice;
                    _adCompanyCount = aCount;
                    _eventsAnalyticsUnitPrice = evPrice;
                    _eventsAnalyticsCount = evCount;
                    _eventsAnalyticsTitle = evTitle;
                    _settlementAmount = sAmount;
                    _settlementTitle = sTitle;
                    _tashilPercentage = tPerc;
                    _marketPercentage = mPerc;
                    _accountantPercentage = accPerc;
                  });

                  _savePreferences();
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 0,
          title: const Text(
            'Collections & Invoices',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14.5,
              letterSpacing: -0.2,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune_rounded, size: 20),
              tooltip: 'Pricing & Ratios Settings',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _showSettingsDialog,
            ),
            IconButton(
              icon: const Icon(Icons.print_rounded, size: 20),
              tooltip: 'Print Invoice',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _printInvoice,
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
              tooltip: 'Share Invoice',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _shareInvoiceImage,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Refresh Data',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _fetchBillingAndCollectionsData,
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddCollectionDialog,
          icon: const Icon(Icons.add_card_rounded, size: 20),
          label: const Text('Record', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 44),
                      const SizedBox(height: 10),
                      Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _fetchBillingAndCollectionsData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetchBillingAndCollectionsData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Financial Pulse Cards (Total Due | Collected | Remaining)
                      _buildTripleFinancialCards(colorScheme),

                      const SizedBox(height: 16),

                      // 3. Official Invoice Card (Remaining / Gross Switcher + Print/Share)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.description_rounded, color: colorScheme.primary, size: 20),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _showRemainingInvoice ? 'Net Remaining Invoice' : 'Monthly Gross Invoice',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                onPressed: _printInvoice,
                                icon: const Icon(Icons.print_rounded, size: 18),
                                tooltip: 'Print Invoice',
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(width: 6),
                              IconButton.filledTonal(
                                onPressed: _shareInvoiceImage,
                                icon: const Icon(Icons.share_rounded, size: 18),
                                tooltip: 'Share Invoice',
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Responsive M3 Segmented Button Switcher: Remaining vs Gross Total
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.hourglass_top_rounded, size: 16),
                              label: Text(
                                'Net Remaining',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.receipt_long_rounded, size: 16),
                              label: Text(
                                'Monthly Gross',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          selected: {_showRemainingInvoice},
                          onSelectionChanged: (newSelection) {
                            setState(() => _showRemainingInvoice = newSelection.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Screenshot Wrapper for Invoice Table
                      Screenshot(
                        controller: _screenshotController,
                        child: _buildOfficialInvoiceDocument(colorScheme),
                      ),

                      const SizedBox(height: 20),

                      // 4. Collection Transactions Log
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.history_edu_rounded, color: colorScheme.secondary, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                'Collection Log (${_displayedTransactions.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment<bool>(
                                    value: false,
                                    label: Text('All', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  ButtonSegment<bool>(
                                    value: true,
                                    label: Text('This Month', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                selected: {_filterTransactionsByCurrentMonth},
                                onSelectionChanged: (val) {
                                  setState(() {
                                    _filterTransactionsByCurrentMonth = val.first;
                                    _transactionsPage = 0;
                                  });
                                },
                                style: const ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                onPressed: _showAddCollectionDialog,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('Add', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      if (_displayedTransactions.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.pending_actions_rounded, size: 36, color: colorScheme.outline),
                              const SizedBox(height: 6),
                              Text(
                                _filterTransactionsByCurrentMonth
                                    ? 'No collection transactions for ${DateFormat('MMMM yyyy', 'en_US').format(_selectedPeriod)}.'
                                    : 'No collection transactions recorded yet.',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap "Record" below to record new collections.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                              ),
                              if (_filterTransactionsByCurrentMonth && _allCollectionTransactions.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _filterTransactionsByCurrentMonth = false;
                                      _transactionsPage = 0;
                                    });
                                  },
                                  icon: const Icon(Icons.list_alt_rounded, size: 15),
                                  label: Text(
                                    'Show All Months (${_allCollectionTransactions.length} records)',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      else ...[
                        Builder(
                          builder: (context) {
                            final totalCount = _displayedTransactions.length;
                            final totalPages = ((totalCount - 1) ~/ _transactionsPageSize) + 1;
                            final safePage = _transactionsPage.clamp(0, totalPages - 1);
                            final startIndex = safePage * _transactionsPageSize;
                            final endIndex = (startIndex + _transactionsPageSize < totalCount)
                                ? startIndex + _transactionsPageSize
                                : totalCount;
                            final pageItems = _displayedTransactions.sublist(startIndex, endIndex);

                            return Column(
                              children: [
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: pageItems.length,
                                  itemBuilder: (context, index) {
                                    final item = pageItems[index];
                                    return _buildTransactionCard(
                                      item,
                                      colorScheme,
                                      startIndex + index + 1,
                                    );
                                  },
                                ),
                                if (totalPages > 1) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainer,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton.filledTonal(
                                          icon: const Icon(Icons.chevron_left_rounded, size: 20),
                                          tooltip: 'Previous Page',
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          padding: EdgeInsets.zero,
                                          onPressed: safePage > 0
                                              ? () => setState(() => _transactionsPage = safePage - 1)
                                              : null,
                                        ),
                                        Text(
                                          'Page ${safePage + 1} of $totalPages  ($totalCount total)',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                        IconButton.filledTonal(
                                          icon: const Icon(Icons.chevron_right_rounded, size: 20),
                                          tooltip: 'Next Page',
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          padding: EdgeInsets.zero,
                                          onPressed: safePage < totalPages - 1
                                              ? () => setState(() => _transactionsPage = safePage + 1)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }


  /// البطاقات المالية المنسقة والمدمجة (المستحق الكلي | تم تحصيله | المتبقي)
  Widget _buildTripleFinancialCards(ColorScheme colorScheme) {
    return Column(
      children: [
        // 1. Grand Total Due Card (Material Design 3 Seed-Themed)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Due Collections (Grand Total)',
                          style: TextStyle(
                            color: colorScheme.onPrimary.withValues(alpha: 0.75),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatCurrency(_grandTotalDue),
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    direction: Axis.vertical,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_totalDueReceiptsCount Receipts (${_formatAmountOnly(_dueReceiptsTotalAmount)} EGP)',
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      if (_adCompanyCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.onPrimary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$_adCompanyCount Ad Cos (${_formatAmountOnly(_adCompanyTotalAmount)} EGP)',
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (_eventsAnalyticsCount > 0 || _settlementAmount > 0) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (_eventsAnalyticsCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.onPrimary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.analytics_outlined, size: 12, color: colorScheme.onPrimary),
                            const SizedBox(width: 4),
                            Text(
                              '+${_formatAmountOnly(_eventsAnalyticsTotalAmount)} Events Soft.',
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_settlementAmount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.onPrimary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle_outline_rounded, size: 12, color: colorScheme.onPrimary),
                            const SizedBox(width: 4),
                            Text(
                              '+${_formatAmountOnly(_settlementAmount)} Settlement',
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Divider(color: colorScheme.onPrimary.withValues(alpha: 0.2), height: 1),
              const SizedBox(height: 8),

              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Tashil (70%): ${_formatCurrency(_tashilDueAmount)}',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Fathalla (30%): ${_formatCurrency(_marketDueAmount)}',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 2. Collected & Remaining Cards (Dynamic M3 ColorScheme Tonal Containers)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Collected Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle_rounded, size: 15, color: colorScheme.onTertiaryContainer),
                              const SizedBox(width: 4),
                              Text(
                                'Collected',
                                style: TextStyle(
                                  color: colorScheme.onTertiaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_totalCollectedReceiptsCount Rec • $_totalCollectedAdCompaniesCount Ad${_totalCollectedEventsAnalyticsCount > 0 ? ' • $_totalCollectedEventsAnalyticsCount Ev' : ''}',
                            style: TextStyle(
                              color: colorScheme.onTertiaryContainer.withValues(alpha: 0.8),
                              fontSize: 9.0,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatCurrency(_totalCollectedAmount),
                            style: TextStyle(
                              color: colorScheme.onTertiaryContainer,
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              Text(
                                'Tashil: ${_formatAmountOnly(_tashilCollectedAmount)}',
                                style: TextStyle(
                                  color: colorScheme.onTertiaryContainer.withValues(alpha: 0.75),
                                  fontSize: 8.5,
                                ),
                              ),
                              Text(
                                '| Fathalla: ${_formatAmountOnly(_marketCollectedAmount)}',
                                style: TextStyle(
                                  color: colorScheme.onTertiaryContainer.withValues(alpha: 0.75),
                                  fontSize: 8.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.onTertiaryContainer.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pie_chart_rounded, size: 11, color: colorScheme.onTertiaryContainer),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Progress: ${_collectionProgressPercentage.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: colorScheme.onTertiaryContainer,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Remaining Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.hourglass_top_rounded, size: 15, color: colorScheme.onErrorContainer),
                              const SizedBox(width: 4),
                              Text(
                                'Remaining',
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_remainingReceiptsCount Rec • $_remainingAdCompaniesCount Ad${_remainingEventsAnalyticsCount > 0 ? ' • $_remainingEventsAnalyticsCount Ev' : ''}',
                            style: TextStyle(
                              color: colorScheme.onErrorContainer.withValues(alpha: 0.8),
                              fontSize: 9.0,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatCurrency(_remainingBalanceAmount),
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              Text(
                                'Tashil: ${_formatAmountOnly(_tashilRemainingAmount)}',
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer.withValues(alpha: 0.75),
                                  fontSize: 8.5,
                                ),
                              ),
                              Text(
                                '| Fathalla: ${_formatAmountOnly(_marketRemainingAmount)}',
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer.withValues(alpha: 0.75),
                                  fontSize: 8.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colorScheme.onErrorContainer.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet_rounded, size: 11, color: colorScheme.onErrorContainer),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Accountant (${_accountantPercentage.toStringAsFixed(0)}%): ${_formatCurrency(_accountantRemainingAmount)}',
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Monthly Progress Indicator (M3 SurfaceContainer)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Monthly Collection Progress:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    '${_collectionProgressPercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _collectionProgressPercentage / 100.0,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// الفاتورة الرسمية المعتمدة بتصميم منسق ومدمج 100% باللغة الإنجليزية ومن اليسار لليمين (LTR)
  Widget _buildOfficialInvoiceDocument(ColorScheme colorScheme) {
    final invoiceDateStr = DateFormat('d/M/yyyy').format(_selectedPeriod);
    final servicePeriodStr = DateFormat('MMM-yy', 'en_US').format(_selectedPeriod);
    final invoiceNo = '${_selectedPeriod.year}${_selectedPeriod.month}000/46';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header Information Section (LTR: Bill To on left, Invoice Details on right)
            Table(
              border: TableBorder.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 0.8),
              columnWidths: const {
                0: FlexColumnWidth(1.15),
                1: FlexColumnWidth(1.0),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Text(
                        'Bill To',
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 11),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Text(
                        'Invoice Details',
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text('Customer: Fathalla Market', style: TextStyle(fontSize: 10, color: colorScheme.onSurface)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text('Invoice No: $invoiceNo', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text('Attn: Mr. Mohamed A. Hassan', style: TextStyle(fontSize: 10, color: colorScheme.onSurface)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text('Date: $invoiceDateStr', style: TextStyle(fontSize: 10, color: colorScheme.onSurface)),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text(
                        _showRemainingInvoice ? 'Type: Net Remaining Balance' : 'Company: All Companies',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text('Period: $servicePeriodStr', style: TextStyle(fontSize: 10, color: colorScheme.onSurface)),
                    ),
                  ],
                ),
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text('System: Tashil Business', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text('Payment: Official / Cash', style: TextStyle(fontSize: 10, color: colorScheme.onSurface)),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 2. Main Items Table (LTR: Description -> Qty -> Price -> Total (EGP))
            Table(
              border: TableBorder.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 0.8),
              columnWidths: const {
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(0.7),
                2: FlexColumnWidth(1.0),
                3: FlexColumnWidth(1.3),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: colorScheme.primary),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Text(
                        'Description',
                        style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 10.5),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      child: Text(
                        'Qty',
                        style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 10.5),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      child: Text(
                        'Price',
                        style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 10.5),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Text(
                        'Total (EGP)',
                        style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 10.5),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),

                // Item 1: Electronic Receipts (Shown only if Qty > 0 or Total > 0)
                if (_invoiceReceiptsQty > 0 || _invoiceReceiptsTotal > 0)
                  TableRow(
                    decoration: BoxDecoration(color: colorScheme.surface),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Text(
                          _showRemainingInvoice
                              ? 'Issuing official electronic payment receipts\n(Remaining Balance)'
                              : 'Issuing official electronic payment receipts',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Text(
                          NumberFormat('#,##0').format(_invoiceReceiptsQty),
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Text(
                          _formatAmountOnly(_receiptUnitPrice),
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Text(
                          _formatAmountOnly(_invoiceReceiptsTotal),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),

                // Item 2: Advertising Company Subscription (Shown only if Qty > 0 or Total > 0)
                if (_invoiceAdCompaniesQty > 0 || _invoiceAdCompaniesTotal > 0)
                  TableRow(
                    decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Text(
                          _showRemainingInvoice
                              ? 'Advertising Company Subscription\n(Remaining Balance)'
                              : 'Advertising Company Subscription',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Text(
                          '$_invoiceAdCompaniesQty',
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Text(
                          _formatAmountOnly(_adCompanyUnitPrice),
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Text(
                          _formatAmountOnly(_invoiceAdCompaniesTotal),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),

                // Item 3: Events Analytics Software Subscription (Shown only if Qty > 0 or Total > 0)
                if (_invoiceEventsAnalyticsQty > 0 || _invoiceEventsAnalyticsTotal > 0)
                  TableRow(
                    decoration: BoxDecoration(color: colorScheme.surface),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Text(
                          _showRemainingInvoice
                              ? (_eventsAnalyticsTitle.isNotEmpty
                                  ? '$_eventsAnalyticsTitle\n(Remaining Balance)'
                                  : 'Events Analytics Software Subscription\n(Remaining Balance)')
                              : (_eventsAnalyticsTitle.isNotEmpty
                                  ? _eventsAnalyticsTitle
                                  : 'Events Analytics Software Subscription'),
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Text(
                          '$_invoiceEventsAnalyticsQty',
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Text(
                          _formatAmountOnly(_eventsAnalyticsUnitPrice),
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Text(
                          _formatAmountOnly(_invoiceEventsAnalyticsTotal),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),

                // Item 4: Settlement & Additional Adjustments (Shown only if Total > 0)
                if (_invoiceSettlementTotal > 0)
                  TableRow(
                    decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Text(
                          _showRemainingInvoice
                              ? (_settlementTitle.isNotEmpty
                                  ? '$_settlementTitle\n(Remaining Balance)'
                                  : 'Settlement & Additional Adjustments\n(Remaining Balance)')
                              : (_settlementTitle.isNotEmpty
                                  ? _settlementTitle
                                  : 'Settlement & Additional Adjustments'),
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Text(
                          '1',
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Text(
                          _formatAmountOnly(_invoiceSettlementTotal),
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Text(
                          _formatAmountOnly(_invoiceSettlementTotal),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),

                // Fallback row if all items are fully settled
                if ((_invoiceReceiptsQty <= 0 && _invoiceReceiptsTotal <= 0) &&
                    (_invoiceAdCompaniesQty <= 0 && _invoiceAdCompaniesTotal <= 0) &&
                    (_invoiceEventsAnalyticsQty <= 0 && _invoiceEventsAnalyticsTotal <= 0) &&
                    _invoiceSettlementTotal <= 0)
                  TableRow(
                    decoration: BoxDecoration(color: colorScheme.surface),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        child: Text(
                          'All monthly dues are fully settled (0.00 EGP remaining)',
                          style: TextStyle(fontSize: 9.5, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                        child: Text('0', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                        child: Text('0.00', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text('0.00', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant), textAlign: TextAlign.right),
                      ),
                    ],
                  ),

                // Grand Total Row
                TableRow(
                  decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Text(''),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      child: Text(''),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      child: Text(
                        _showRemainingInvoice ? 'Net Total' : 'Grand Total',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: colorScheme.primary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Container(
                      color: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Text(
                        _formatAmountOnly(_invoiceGrandTotal),
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onPrimary, fontSize: 10.5),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Written Amount Note (English only)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text(
                _numberToWordsEnglish(_invoiceGrandTotal),
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 9.5,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 6),

            // 3. Payment Split Table (LTR: Payment Split -> Ratio -> Amount (EGP))
            Table(
              border: TableBorder.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 0.8),
              columnWidths: const {
                0: FlexColumnWidth(2.0),
                1: FlexColumnWidth(0.9),
                2: FlexColumnWidth(1.3),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: colorScheme.primary),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: Text(
                        'Payment Split',
                        style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                      child: Text(
                        'Ratio',
                        style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: Text(
                        'Amount (EGP)',
                        style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                TableRow(
                  decoration: BoxDecoration(color: colorScheme.surface),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: Text(
                        'Tashil Delegate Business',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                      child: Text(
                        '${_tashilPercentage.toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 9.5, color: colorScheme.onSurface),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: Text(
                        _formatAmountOnly(_invoiceTashilAmount),
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                TableRow(
                  decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: Text(
                        'Fathalla Market',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                      child: Text(
                        '${_marketPercentage.toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 9.5, color: colorScheme.onSurface),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: Text(
                        _formatAmountOnly(_invoiceMarketAmount),
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                TableRow(
                  decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: Text(
                        'Total',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                      child: Text(
                        '100%',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: Text(
                        _formatAmountOnly(_invoiceGrandTotal),
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    Map<String, dynamic> item,
    ColorScheme colorScheme,
    int index,
  ) {
    final docId = item['id']?.toString() ?? '';
    final itemPeriodKey = item['periodKey']?.toString() ?? '';
    String periodBadge = '';
    if (itemPeriodKey.isNotEmpty) {
      final parts = itemPeriodKey.split('_');
      if (parts.length == 2) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (y != null && m != null) {
          periodBadge = DateFormat('MMM yyyy', 'en_US').format(DateTime(y, m, 1));
        }
      }
    }
    final isCurrentPeriod = itemPeriodKey == _periodKey;

    final recQty = (item['receiptsCount'] as num? ?? 0).toInt();
    final recAmt = (item['receiptsAmount'] as num? ?? (recQty * _receiptUnitPrice)).toDouble();

    final adQty = (item['adCompaniesCount'] as num? ?? 0).toInt();
    final adAmt = (item['adCompaniesAmount'] as num? ?? (adQty * _adCompanyUnitPrice)).toDouble();

    final evQty = (item['eventsAnalyticsCount'] as num? ?? 0).toInt();
    final evAmt = (item['eventsAnalyticsAmount'] as num? ?? (evQty * _eventsAnalyticsUnitPrice)).toDouble();

    final setAmt = (item['settlementAmount'] as num? ?? 0.0).toDouble();

    final amount = (item['collectedAmount'] as num? ?? (recAmt + adAmt + evAmt + setAmt)).toDouble();
    final paymentMethodRaw = item['paymentMethod']?.toString() ?? 'Cash';
    final notes = item['notes']?.toString() ?? '';
    final createdBy = item['createdBy']?.toString() ?? '';
    final createdAt = (item['createdAt'] as Timestamp?)?.toDate();
    final dateStr = createdAt != null ? DateFormat('yyyy-MM-dd  hh:mm a', 'en_US').format(createdAt) : 'N/A';

    String paymentMethod = paymentMethodRaw;
    if (paymentMethodRaw.contains('نقداً') || paymentMethodRaw.toLowerCase() == 'cash') {
      paymentMethod = 'Cash';
    } else if (paymentMethodRaw.contains('تحويل') || paymentMethodRaw.toLowerCase().contains('bank')) {
      paymentMethod = 'Bank Transfer';
    } else if (paymentMethodRaw.contains('شيك') || paymentMethodRaw.toLowerCase().contains('cheque')) {
      paymentMethod = 'Cheque';
    } else if (paymentMethodRaw.contains('إلكتروني') || paymentMethodRaw.toLowerCase().contains('online') || paymentMethodRaw.toLowerCase().contains('card')) {
      paymentMethod = 'Online / Card';
    } else if (paymentMethodRaw.contains('خصم') || paymentMethodRaw.toLowerCase().contains('deduction')) {
      paymentMethod = 'Deduction from Dues';
    }

    // Compose a clear title
    final List<String> entryParts = [];
    if (recQty > 0) entryParts.add('$recQty Receipts');
    if (adQty > 0) entryParts.add('$adQty Ad Cos');
    if (evQty > 0) entryParts.add('$evQty Ev Soft');
    if (setAmt > 0) entryParts.add('Settlement');
    final entryTitle = entryParts.isNotEmpty ? 'Invoice: ${entryParts.join(' + ')}' : 'Invoice';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isCurrentPeriod ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                  foregroundColor: isCurrentPeriod ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                  child: Text('$index', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entryTitle,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (periodBadge.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isCurrentPeriod
                                    ? colorScheme.primaryContainer
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isCurrentPeriod
                                      ? colorScheme.primary.withValues(alpha: 0.4)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                periodBadge,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isCurrentPeriod ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(
                              dateStr,
                              style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatCurrency(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 6),

            // Item Breakdown Chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (recQty > 0 || recAmt > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 11, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Receipts: $recQty (${_formatAmountOnly(recAmt)} EGP)',
                          style: TextStyle(fontSize: 9.5, color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                if (adQty > 0 || adAmt > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.campaign_rounded, size: 11, color: colorScheme.secondary),
                        const SizedBox(width: 4),
                        Text(
                          'Ad Cos: $adQty (${_formatAmountOnly(adAmt)} EGP)',
                          style: TextStyle(fontSize: 9.5, color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                if (evQty > 0 || evAmt > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.analytics_rounded, size: 11, color: colorScheme.tertiary),
                        const SizedBox(width: 4),
                        Text(
                          'Events Soft: $evQty (${_formatAmountOnly(evAmt)} EGP)',
                          style: TextStyle(fontSize: 9.5, color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                if (setAmt > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.balance_rounded, size: 11, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Settlement: ${_formatAmountOnly(setAmt)} EGP',
                          style: TextStyle(fontSize: 9.5, color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            Row(
              children: [
                Chip(
                  label: Text(paymentMethod),
                  avatar: const Icon(Icons.payment_rounded, size: 12),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 10),
                ),
                if (createdBy.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Chip(
                      label: Text(
                        createdBy,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      avatar: const Icon(Icons.person_outline_rounded, size: 12),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      labelStyle: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: colorScheme.outline, size: 18),
                  tooltip: 'Delete Invoice',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _deleteCollectionTransaction(
                    docId,
                    receiptsCount: recQty,
                    receiptsAmount: recAmt,
                    adCompaniesCount: adQty,
                    adCompaniesAmount: adAmt,
                    eventsAnalyticsCount: evQty,
                    eventsAnalyticsAmount: evAmt,
                    settlementAmount: setAmt,
                    totalAmount: amount,
                    transactionPeriodKey: itemPeriodKey,
                  ),
                ),
              ],
            ),

            if (notes.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Notes: $notes',
                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
